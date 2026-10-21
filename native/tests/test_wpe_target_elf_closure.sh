#!/bin/sh
# Fixture: AArch64 ELF produced by clang/lld, never executed or installed.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
AUDIT="$REPO/rocknix-integration/audit-wpe-target-elf-closure.py"
for tool in clang ld.lld readelf python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool required" >&2; exit 2; }
done
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/runtime"
S="$T/rocknix-target-sysroot"
mkdir -p "$R/lib" "$R/libexec/wpe-webkit-2.0" "$S/usr/lib"
printf 'int foo(void) {return 7;}\n' > "$T/foo.c"
printf 'extern int foo(void); void *webkit_web_view_get_wpe_view(void) {return (void *)(long)foo();}\n' > "$T/wpe.c"
printf 'void _start(void) {}\n' > "$T/child.c"
cc() { clang --target=aarch64-unknown-linux-gnu -fuse-ld=lld -nostdlib -fPIC "$@"; }
cc -shared -Wl,-soname,libfoo.so.1 "$T/foo.c" -o "$S/usr/lib/libfoo.so.1"
cc -shared -Wl,-soname,libWPEWebKit-2.0.so.1 "$T/wpe.c" -L"$S/usr/lib" \
  -Wl,-l:libfoo.so.1 -o "$R/lib/libWPEWebKit-2.0.so.1"
for child in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  cc -Wl,-e,_start "$T/child.c" -o "$R/libexec/wpe-webkit-2.0/$child"
done
run() { python3 "$AUDIT" --runtime "$R" --sysroot "$S" "$@"; }
run --strict > "$T/pass"
grep -Fxq 'CLOSURE_STATUS=PASS_STATIC_TARGET_ELF_AUDIT_ONLY' "$T/pass"
mv "$S/usr/lib/libfoo.so.1" "$T/missing-foo"
set +e
run --strict > "$T/missing"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -Fq 'FAIL_MISSING_NEEDED_IN_TARGET=libWPEWebKit-2.0.so.1:libfoo.so.1' "$T/missing"
mv "$T/missing-foo" "$S/usr/lib/libfoo.so.1"
# No host ABI contamination: fake ELF for a dependency is rejected.
printf 'this is not an ELF file' > "$S/usr/lib/libfoo.so.1"
set +e
run --strict > "$T/invalid"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -Fq 'FAIL_BAD_ELF_OR_ARCH=target_sysroot:libfoo.so.1' "$T/invalid"
cc -shared -Wl,-soname,libfoo.so.1 "$T/foo.c" -o "$S/usr/lib/libfoo.so.1"
# Legitimate WPE subprocess runpath can climb to private lib *within* runtime.
cc -Wl,-e,_start -Wl,-rpath,'$ORIGIN/../../lib' "$T/child.c" \
  -o "$R/libexec/wpe-webkit-2.0/WPEWebProcess"
run --strict > "$T/origin-pass"
grep -Fxq 'CLOSURE_STATUS=PASS_STATIC_TARGET_ELF_AUDIT_ONLY' "$T/origin-pass"
# But it must never escape the isolated runtime tree.
cc -Wl,-e,_start -Wl,-rpath,'$ORIGIN/../../../../../../host' "$T/child.c" \
  -o "$R/libexec/wpe-webkit-2.0/WPEWebProcess"
set +e
run --strict > "$T/origin-escape"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -Fq 'FAIL_UNSAFE_RUNPATH=runtime:WPEWebProcess:' "$T/origin-escape"
cc -Wl,-e,_start "$T/child.c" -o "$R/libexec/wpe-webkit-2.0/WPEWebProcess"
# Explicitly reject a misplaced absolute host runpath.
cc -shared -Wl,-soname,libWPEWebKit-2.0.so.1 -Wl,-rpath,/tmp/host-x86 \
  "$T/wpe.c" -L"$S/usr/lib" -Wl,-l:libfoo.so.1 -o "$R/lib/libWPEWebKit-2.0.so.1"
set +e
run --strict > "$T/runpath"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -Fq 'FAIL_UNSAFE_RUNPATH=runtime:libWPEWebKit-2.0.so.1:/tmp/host-x86' "$T/runpath"
# Media-free profile must not load GStreamer even if the symbols resolve.
cc -shared -Wl,-soname,libgstvideo-1.0.so.0 "$T/foo.c" -o "$S/usr/lib/libgstvideo-1.0.so.0"
cc -shared -Wl,-soname,libWPEWebKit-2.0.so.1 "$T/wpe.c" -L"$S/usr/lib" \
  -Wl,-l:libgstvideo-1.0.so.0 -o "$R/lib/libWPEWebKit-2.0.so.1"
set +e
run --strict > "$T/gst"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -Fq 'FAIL_GSTREAMER_LINKED=runtime:libWPEWebKit-2.0.so.1:libgstvideo-1.0.so.0' "$T/gst"
# Inspect reports the problem without blocking reports collection.
run --inspect > "$T/inspect"
grep -Fxq 'CLOSURE_STATUS=BLOCKED' "$T/inspect"
echo 'PASS: real AArch64 ELF, dependency resolution, invalid target ELF, host runpath and forbidden GStreamer'
echo 'LIMIT: fixtures are not a real ROCKNIX SDK or functional WPE WebKit'
