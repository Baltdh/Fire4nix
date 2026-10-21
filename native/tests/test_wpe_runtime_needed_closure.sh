#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/runtime/lib" "$tmp/rootfs/usr/lib"
# Mock ELF binaries: the checker must inspect DT_NEEDED, not merely ELF headers.
printf 'int foo(void) { return 0; }\n' > "$tmp/foo.c"
printf 'extern int foo(void); int bar(void) { return foo(); }\n' > "$tmp/bar.c"
gcc -shared -fPIC "$tmp/foo.c" -Wl,-soname,libfixture-foo.so.1 -o "$tmp/rootfs/usr/lib/libfixture-foo.so.1"
gcc -shared -fPIC "$tmp/bar.c" -L"$tmp/rootfs/usr/lib" -l:libfixture-foo.so.1 \
 -Wl,-soname,libfixture-bar.so.1 -o "$tmp/runtime/lib/libfixture-bar.so.1"
python3 "$repo/rocknix-integration/audit-wpe-runtime-needed-closure.py" \
 --runtime "$tmp/runtime" --rootfs "$tmp/rootfs" > "$tmp/good"
grep -Fxq 'DT_NEEDED_CLOSURE=SONAME_PRESENT_ONLY_ABI_NOT_PROVEN' "$tmp/good"
rm -f "$tmp/rootfs/usr/lib/libfixture-foo.so.1"
if python3 "$repo/rocknix-integration/audit-wpe-runtime-needed-closure.py" \
 --runtime "$tmp/runtime" --rootfs "$tmp/rootfs" > "$tmp/missing"; then
 echo 'FAIL: missing SONAME was accepted' >&2; exit 1
fi
grep -q 'MISSING_NEEDED=.*libfixture-foo.so.1' "$tmp/missing"
grep -Fxq 'DT_NEEDED_CLOSURE=BLOCKED' "$tmp/missing"
# Reject build-host absolute RPATH leakage.
gcc -shared -fPIC "$tmp/foo.c" -Wl,-rpath,/home/runner/unsafe \
 -Wl,-soname,libfixture-foo.so.1 -o "$tmp/runtime/lib/libfixture-foo.so.1"
if python3 "$repo/rocknix-integration/audit-wpe-runtime-needed-closure.py" \
 --runtime "$tmp/runtime" --rootfs "$tmp/rootfs" > "$tmp/rpath"; then
 echo 'FAIL: build host RPATH accepted' >&2; exit 1
fi
grep -q '^UNSAFE_DYNAMIC_PATH=' "$tmp/rpath"
echo 'PASS: dynamic SONAME closure accepts present rootfs ELF and rejects missing deps/RPATH leakage'
