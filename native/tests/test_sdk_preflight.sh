#!/bin/sh
# Offline mocked regression checks. Does not claim to validate a real SDK.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sysroot/usr/lib" "$tmp/bin"
: > "$tmp/toolchain.cmake"
printf 'mock target libc\n' > "$tmp/sysroot/usr/lib/libc.so.6"
cat > "$tmp/bin/readelf" <<'FAKE'
#!/bin/sh
case "$1" in
  -h) printf '  Machine: %s\n' "${MOCK_ARCH:-AArch64}" ;;
  -V)
    printf 'Name: GLIBC_2.17\nName: GLIBC_%s\n' "${MOCK_GLIBC:-2.41}" ;;
  *) exit 3 ;;
esac
FAKE
chmod +x "$tmp/bin/readelf"
checker="$root/rocknix-integration/check-rocknix-sdk.sh"
builder="$root/rocknix-integration/build-wpe-2.54.1.sh"
run_check() {
  FIRE4NIX_ROCKNIX_TOOLCHAIN="$tmp/toolchain.cmake" \
  FIRE4NIX_ROCKNIX_SYSROOT="$tmp/sysroot" \
  PATH="$tmp/bin:$PATH" sh "$checker" --check
}
run_check > "$tmp/pass.txt"
grep -q 'SDK_PREFLIGHT=PASS' "$tmp/pass.txt"
grep -q 'target_glibc=2.41' "$tmp/pass.txt"
MOCK_ARCH=x86-64 run_check > "$tmp/arch.txt" 2>&1 && { echo 'FAIL: accepted wrong machine'; exit 1; } || :
grep -q 'not an AArch64 ELF' "$tmp/arch.txt"
MOCK_GLIBC=2.44 run_check > "$tmp/glibc.txt" 2>&1 && { echo 'FAIL: accepted newer glibc'; exit 1; } || :
grep -q 'GLIBC_2.44 differs' "$tmp/glibc.txt"
FIRE4NIX_ROCKNIX_RELEASE=20261001 MOCK_GLIBC=2.44 run_check > "$tmp/new-release.txt"
grep -q 'target_glibc=2.44' "$tmp/new-release.txt"
FIRE4NIX_ROCKNIX_RELEASE=bad run_check > "$tmp/release.txt" 2>&1 && { echo 'FAIL: accepted unsupported release'; exit 1; } || :
grep -q 'unsupported ROCKNIX release' "$tmp/release.txt"
FIRE4NIX_ROCKNIX_TOOLCHAIN="$tmp/toolchain.cmake" FIRE4NIX_ROCKNIX_SYSROOT=/ \
  PATH="$tmp/bin:$PATH" sh "$checker" --check > "$tmp/host.txt" 2>&1 && { echo 'FAIL: accepted host root'; exit 1; } || :
grep -q 'refusing host root' "$tmp/host.txt"
mv "$tmp/sysroot/usr/lib/libc.so.6" "$tmp/libc-saved"
ln -s "$tmp/libc-saved" "$tmp/sysroot/usr/lib/libc.so.6"
run_check > "$tmp/escape.txt" 2>&1 && { echo 'FAIL: accepted libc symlink escape'; exit 1; } || :
grep -q 'outside the sysroot' "$tmp/escape.txt"
rm "$tmp/sysroot/usr/lib/libc.so.6"
mv "$tmp/libc-saved" "$tmp/sysroot/usr/lib/libc.so.6"
FIRE4NIX_ROCKNIX_TOOLCHAIN="$tmp/toolchain.cmake" \
 FIRE4NIX_ROCKNIX_SYSROOT="$tmp/sysroot" PATH="$tmp/bin:$PATH" \
 sh "$builder" --preflight > "$tmp/build-preflight.txt"
grep -q 'SDK_PREFLIGHT=PASS' "$tmp/build-preflight.txt"
FIRE4NIX_ROCKNIX_TOOLCHAIN="$tmp/toolchain.cmake" \
 FIRE4NIX_ROCKNIX_SYSROOT="$tmp/sysroot" MOCK_GLIBC=2.44 PATH="$tmp/bin:$PATH" \
 sh "$builder" --preflight > "$tmp/build-refuse.txt" 2>&1 && { echo 'FAIL: builder bypassed guard'; exit 1; } || :
grep -q 'GLIBC_2.44 differs' "$tmp/build-refuse.txt"
echo 'PASS: SDK preflight rejects host/wrong ABI, glibc mismatch and symlink escape (mock only)'
