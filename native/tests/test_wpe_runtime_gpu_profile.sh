#!/bin/sh
# Native AArch64 CI fixtures for explicit WPE GPUProcess staging policy.
set -eu
command -v cc >/dev/null
command -v readelf >/dev/null
SCRIPT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)/rocknix-integration/stage-wpe-runtime.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/install/usr/lib" "$tmp/install/usr/libexec/wpe-webkit-2.0"
# Same architecture as the R36H when running on ubuntu-24.04-arm.
printf 'int webkit_web_view_get_wpe_view(void) { return 1; }\n' |
 cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 -x c - \
 -o "$tmp/install/usr/lib/libWPEWebKit-2.0.so.1"
for p in WPEWebProcess WPENetworkProcess; do
 printf 'int main(void) { return 0; }\n' |
   cc -x c - -o "$tmp/install/usr/libexec/wpe-webkit-2.0/$p"
done
readelf -h "$tmp/install/usr/lib/libWPEWebKit-2.0.so.1" | grep -q 'Machine:.*AArch64'
stage() {
 FIRE4NIX_WPE_DESTDIR="$tmp/install" \
 FIRE4NIX_WPE_RUNTIME_OUT="$tmp/$1" \
 FIRE4NIX_WPE_CMAKE_CACHE="$2" \
 FIRE4NIX_REQUIRE_MEDIA_FREE=1 \
 sh "$SCRIPT" --stage
}
# No trusted configure cache => a missing GPUProcess is a hard failure.
if FIRE4NIX_WPE_DESTDIR="$tmp/install" FIRE4NIX_WPE_RUNTIME_OUT="$tmp/unsafe" \
 FIRE4NIX_REQUIRE_MEDIA_FREE=1 sh "$SCRIPT" --stage >/dev/null 2>&1; then
 echo 'FAIL: GPUProcess absence accepted without CMakeCache' >&2; exit 1
fi
cat > "$tmp/gpu-off-cache" <<'EOF'
ENABLE_GPU_PROCESS:BOOL=OFF
ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON
USE_GSTREAMER:BOOL=OFF
USE_GBM:BOOL=OFF
USE_LIBDRM:BOOL=OFF
EOF
stage "off" "$tmp/gpu-off-cache" > "$tmp/off-result.txt"
test -s "$tmp/off/libexec/wpe-webkit-2.0/WPEWebProcess"
test -s "$tmp/off/libexec/wpe-webkit-2.0/WPENetworkProcess"
test ! -e "$tmp/off/libexec/wpe-webkit-2.0/WPEGPUProcess"
grep -Fxq 'GPU_PROCESS_PROFILE=disabled_verified_wayland' "$tmp/off/BUILD-REPORT.txt"
test "$(wc -l < "$tmp/off/SHA256SUMS.txt")" -eq 3
grep -Fxq 'PROFILE=MEDIA_FREE VERIFIED' "$tmp/off/MEDIA-PROFILE.txt"
# A doctored cache must never silently relax the GPU binary requirement.
sed '/USE_LIBDRM:BOOL=OFF/d' "$tmp/gpu-off-cache" > "$tmp/bad-cache"
if stage "bad" "$tmp/bad-cache" > /dev/null 2>&1; then
 echo 'FAIL: unverified Wayland profile accepted' >&2; exit 1
fi
cat > "$tmp/gpu-on-cache" <<'EOF'
ENABLE_GPU_PROCESS:BOOL=ON
EOF
if stage "missing-gpu" "$tmp/gpu-on-cache" > /dev/null 2>&1; then
 echo 'FAIL: GPUProcess enabled but binary missing' >&2; exit 1
fi
printf 'int main(void) { return 0; }\n' |
 cc -x c - -o "$tmp/install/usr/libexec/wpe-webkit-2.0/WPEGPUProcess"
stage "on" "$tmp/gpu-on-cache" > "$tmp/on-result.txt"
test -s "$tmp/on/libexec/wpe-webkit-2.0/WPEGPUProcess"
grep -Fxq 'GPU_PROCESS_PROFILE=enabled_verified' "$tmp/on/BUILD-REPORT.txt"
test "$(wc -l < "$tmp/on/SHA256SUMS.txt")" -eq 4
echo 'WPE_GPU_STAGING_REGRESSION=PASS_ARM64_REAL_ELF_FIXTURES'
