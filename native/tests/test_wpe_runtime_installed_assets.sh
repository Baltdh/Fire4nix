#!/bin/sh
# Real ELF64/AArch64 fixture regression for WPE 2.54.1 installed asset staging.
# This never builds or installs the browser on the actual console.
set -eu
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: native AArch64 CI required'; exit 2; }
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
stager="$root/rocknix-integration/stage-wpe-runtime.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
base="$tmp/install"
mkdir -p "$base/usr/lib/wpe-webkit-2.0/injected-bundle" \
 "$base/usr/libexec/wpe-webkit-2.0" "$base/usr/share/wpe-webkit-2.0"
cat > "$tmp/lib.c" <<'EOF'
int webkit_web_view_get_wpe_view(void) { return 42; }
EOF
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 \
 "$tmp/lib.c" -o "$base/usr/lib/libWPEWebKit-2.0.so.1"
cat > "$tmp/bundle.c" <<'EOF'
int wpe_injected_bundle_entry(void) { return 42; }
EOF
cc -shared -fPIC "$tmp/bundle.c" \
 -o "$base/usr/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
echo 'WPE inspector.gresource fixture only' > "$base/usr/share/wpe-webkit-2.0/inspector.gresource"
mkdir -p "$base/usr/share/wpe-webkit-2.0/css"
echo 'body{}' > "$base/usr/share/wpe-webkit-2.0/css/inspector.css"
cat > "$tmp/process.c" <<'EOF'
int main(void) { return 0; }
EOF
for child in WPEWebProcess WPENetworkProcess; do
 cc -fPIE -pie "$tmp/process.c" -o "$base/usr/libexec/wpe-webkit-2.0/$child"
done
cat > "$tmp/CMakeCache.txt" <<'EOF'
ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON
ENABLE_GPU_PROCESS:BOOL=OFF
USE_GSTREAMER:BOOL=OFF
USE_GBM:BOOL=OFF
USE_LIBDRM:BOOL=OFF
EOF
stage() {
 FIRE4NIX_WPE_DESTDIR="$base" \
 FIRE4NIX_WPE_RUNTIME_OUT="$tmp/$1" \
 FIRE4NIX_WPE_ASSETS_PROFILE=strict \
 FIRE4NIX_WPE_CMAKE_CACHE="$tmp/CMakeCache.txt" \
 FIRE4NIX_REQUIRE_MEDIA_FREE=1 \
 sh "$stager" --stage
}
stage accepted > "$tmp/accepted.txt"
test -s "$tmp/accepted/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
test -s "$tmp/accepted/share/wpe-webkit-2.0/inspector.gresource"
test -s "$tmp/accepted/share/wpe-webkit-2.0/css/inspector.css"
grep -Fxq 'WPE_INSTALLED_ASSETS_PROFILE=strict' "$tmp/accepted/BUILD-REPORT.txt"
grep -Fxq 'WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked' "$tmp/accepted/BUILD-REPORT.txt"
(cd "$tmp/accepted" && sha256sum -c SHA256SUMS.txt >/dev/null)
test "$(wc -l < "$tmp/accepted/SHA256SUMS.txt")" -eq 6

# Missing inspector means incomplete, not a valid runtime.
rm "$base/usr/share/wpe-webkit-2.0/inspector.gresource"
if stage no-inspector > /dev/null 2>&1; then
 echo 'ERROR: missing installed inspector resources accepted' >&2; exit 1
fi
echo 'WPE inspector fixture' > "$base/usr/share/wpe-webkit-2.0/inspector.gresource"

# Absolute or escaping file links are never distributed as WPE resources.
ln -s /etc/passwd "$base/usr/share/wpe-webkit-2.0/css/bad.css"
if stage bad-link > /dev/null 2>&1; then
 echo 'ERROR: symlink escaped WPE installed resources' >&2; exit 1
fi
rm "$base/usr/share/wpe-webkit-2.0/css/bad.css"

# A non-ELF module is not accepted simply because its filename is .so.
printf 'not an ARM64 ELF\n' > "$base/usr/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
if stage invalid-injected > /dev/null 2>&1; then
 echo 'ERROR: invalid injected bundle accepted' >&2; exit 1
fi
cc -shared -fPIC "$tmp/bundle.c" \
 -o "$base/usr/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"

# Explicit opt-in must not silently fall back to optional asset copying.
rm -rf "$base/usr/share/wpe-webkit-2.0"
if stage missing-directory > /dev/null 2>&1; then
 echo 'ERROR: strict profile accepted missing resources' >&2; exit 1
fi
echo 'WPE_INSTALL_RESOURCE_STAGE=PASS_REAL_AARCH64_FIXTURE'
