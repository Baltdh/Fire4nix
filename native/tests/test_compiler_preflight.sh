#!/bin/sh
# Fail-closed tests: invalid toolchain/SDK must be refused before WPE compiles.
# No large WPE source build or device access; this suite has no valid ROCKNIX SDK.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/sysroot/usr/lib"
printf 'fake ELF, must be rejected\n' > "$t/sysroot/usr/lib/libc.so.6"
cat > "$t/toolchain.cmake" <<'CMAKE'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
# Deliberately omit CMAKE_SYSROOT. Must never be accepted.
CMAKE
checker="$root/rocknix-integration/check-rocknix-compiler.sh"
builder="$root/rocknix-integration/build-wpe-2.54.1.sh"
for script in "$checker" "$builder"; do sh -n "$script"; done
if FIRE4NIX_ROCKNIX_SYSROOT="$t/sysroot" \
   FIRE4NIX_ROCKNIX_TOOLCHAIN="$t/toolchain.cmake" \
   sh "$checker" --check > "$t/invalid.log" 2>&1; then
  echo 'FAIL: bad sysroot unexpectedly accepted'; exit 1
fi
grep -q 'not an AArch64 ELF' "$t/invalid.log"
if FIRE4NIX_ROCKNIX_SYSROOT="$t/sysroot" \
   FIRE4NIX_ROCKNIX_TOOLCHAIN="$t/toolchain.cmake" \
   sh "$builder" --probe-compiler > "$t/probe.log" 2>&1; then
  echo 'FAIL: build recipe bypassed compiler guard'; exit 1
fi
grep -q 'not an AArch64 ELF' "$t/probe.log"
# For malformed input or unavailable tools the compiler must fail closed.
if FIRE4NIX_ROCKNIX_SYSROOT=/ \
   FIRE4NIX_ROCKNIX_TOOLCHAIN="$t/toolchain.cmake" \
   sh "$checker" --check > "$t/host.log" 2>&1; then
  echo 'FAIL: host root unexpectedly accepted'; exit 1
fi
grep -Eq 'host /|refusing host root' "$t/host.log"
echo 'PASS: bad SDK and host roots rejected before CMake/WebKit (negative fixture only)'
