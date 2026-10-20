#!/bin/sh
# Host-side static fixture tests only. Not a test of hardware graphics/ABI.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
SCRIPT=$REPO/rocknix-integration/inspect-wpe-dependencies.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/runtime/lib" "$T/sys" "$T/runtime/libexec/wpe-webkit-2.0"
cat > "$T/base.c" <<'SRC'
int dependency(void){return 7;}
SRC
cc -shared -fPIC "$T/base.c" -Wl,-soname,libexample.so.1 -o "$T/sys/libexample.so.1"
cat > "$T/user.c" <<'SRC'
extern int dependency(void);
int webkit_mock(void){ return dependency(); }
SRC
cc -shared -fPIC "$T/user.c" -L"$T/sys" -l:libexample.so.1 -o "$T/runtime/lib/libWPEWebKit-2.0.so.1"
MACHINE=$(readelf -h "$T/sys/libexample.so.1" | sed -n 's/.*Machine: *//p' | sed -n '1p')
# libc is a controlled symlink, not an OS modification.
SYS_LIBC=$(ldconfig -p | awk '/libc\.so\.6 \(/ {print $NF; exit}')
[ -n "$SYS_LIBC" ] && ln -s "$SYS_LIBC" "$T/sys/libc.so.6"
FIRE4NIX_EXPECTED_MACHINE="$MACHINE" FIRE4NIX_ABI_SYSTEM_DIRS="$T/sys" FIRE4NIX_ABI_REPORT="$T/pass.txt" sh "$SCRIPT" --strict "$T/runtime" >/dev/null
grep -q '^status=STATIC_DEPENDENCIES_FOUND_NOT_EXECUTION_VERIFIED$' "$T/pass.txt"
grep -q 'NEEDED=libexample.so.1' "$T/pass.txt"
grep -q "RESOLVED=libexample.so.1 -> $T/sys/libexample.so.1" "$T/pass.txt"
# A character-device placeholder must never count as a working ELF.
mv "$T/sys/libexample.so.1" "$T/sys/real-elf"
ln -s /dev/null "$T/sys/libexample.so.1"
set +e
FIRE4NIX_EXPECTED_MACHINE="$MACHINE" FIRE4NIX_ABI_SYSTEM_DIRS="$T/sys" FIRE4NIX_ABI_REPORT="$T/fail.txt" sh "$SCRIPT" --strict "$T/runtime" >/dev/null
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -q "REJECT_CANDIDATE=$T/sys/libexample.so.1" "$T/fail.txt"
grep -q '^status=BLOCK_INCOMPLETE_DEPENDENCIES$' "$T/fail.txt"
rm "$T/sys/libexample.so.1"
ln -s real-elf "$T/sys/libexample.so.1"
FIRE4NIX_EXPECTED_MACHINE="$MACHINE" FIRE4NIX_ABI_SYSTEM_DIRS="$T/sys" FIRE4NIX_ABI_REPORT="$T/again.txt" sh "$SCRIPT" --strict "$T/runtime" >/dev/null
printf 'damaged' > "$T/runtime/lib/libgstvideo-1.0.so.0"
set +e
FIRE4NIX_EXPECTED_MACHINE="$MACHINE" FIRE4NIX_ABI_SYSTEM_DIRS="$T/sys" FIRE4NIX_ABI_REPORT="$T/corrupt.txt" sh "$SCRIPT" --strict "$T/runtime" >/dev/null
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -q 'INVALID_ELF_OR_MACHINE=' "$T/corrupt.txt"
echo 'PASS: NEEDED resolution; reject /dev/null; detect invalid ELF; strict exit 6'
