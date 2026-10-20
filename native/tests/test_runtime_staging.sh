#!/bin/sh
# CI mock exercise: does NOT build an actual WebKit or claim Mali support.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/staged/usr/lib" "$T/staged/usr/libexec/wpe-webkit-2.0"
[ -f /tmp/modern-wpe/libWPEWebKit-2.0.so.1 ] || { echo 'Run after the WPE ABI mock build' >&2; exit 2; }
cp /tmp/modern-wpe/libWPEWebKit-2.0.so.1 "$T/staged/usr/lib/"
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  cp "$ROOT/out/Fire4Nix/bin/fire4nix-native-aarch64" "$T/staged/usr/libexec/wpe-webkit-2.0/$p"
done
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/runtime" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/staged.log"
grep -q 'STATUS=ELF_VERIFIED_DEPENDENCIES_AND_REAL_WAYLAND_UNTESTED' "$T/staged.log"
test -s "$T/runtime/lib/libWPEWebKit-2.0.so.1"
test -s "$T/runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
grep -q 'AArch64 ELF and WPEPlatform exported symbol checked' "$T/runtime/BUILD-REPORT.txt"
(cd "$T/runtime" && sha256sum -c SHA256SUMS.txt >/dev/null)
set +e
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/runtime" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/overwrite.log" 2>&1
overwrite=$?
set -e
test "$overwrite" -eq 2
grep -q 'already exists' "$T/overwrite.log"
# An incomplete WPE stage must not create any output.
rm -f "$T/staged/usr/libexec/wpe-webkit-2.0/WPEGPUProcess"
set +e
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/incomplete" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/missing-child.log" 2>&1
missing=$?
set -e
test "$missing" -eq 3
test ! -e "$T/incomplete"
grep -q 'missing staged WPEGPUProcess' "$T/missing-child.log"
# Even a perfectly valid AArch64 ELF must be rejected if its required
# GLIBC symbols are newer than the target R36H (reported 2.41).
mkdir -p "$T/fake-bin"
cat > "$T/fake-bin/readelf" <<'READELF'
#!/bin/sh
if [ "${1:-}" = -V ] && [ "${FIRE4NIX_TEST_NEWER_GLIBC:-0}" = 1 ]; then
  echo '  Name: GLIBC_2.44  Flags: none  Version: 2'
  exit 0
fi
exec /usr/bin/readelf "$@"
READELF
chmod +x "$T/fake-bin/readelf"
# Restore missing subprocess; failure should now be specifically ABI-related.
cp "$ROOT/out/Fire4Nix/bin/fire4nix-native-aarch64" "$T/staged/usr/libexec/wpe-webkit-2.0/WPEGPUProcess"
set +e
FIRE4NIX_TEST_NEWER_GLIBC=1 PATH="$T/fake-bin:$PATH" \
  FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/too-new" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/too-new.log" 2>&1
too_new=$?
set -e
test "$too_new" -eq 4
grep -q 'needs GLIBC_2.44; device limit is GLIBC_2.41' "$T/too-new.log"
test ! -e "$T/too-new"
# A media-free build must reject any direct libgst dependency, even if the
# host can otherwise resolve it. Use a readelf shim so no actual WebKit is built.
FIRE4NIX_REQUIRE_MEDIA_FREE=1 \
 FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/media-free" \
 sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/media-free.log"
grep -q 'PROFILE=MEDIA_FREE VERIFIED' "$T/media-free/MEDIA-PROFILE.txt"
cat > "$T/fake-bin/readelf" <<'READELF'
#!/bin/sh
if [ "${1:-}" = -d ] && [ "${FIRE4NIX_TEST_FAKE_GST:-0}" = 1 ]; then
  echo ' 0x1 (NEEDED) Shared library: [libgstvideo-1.0.so.0]'
  exit 0
fi
if [ "${1:-}" = -V ] && [ "${FIRE4NIX_TEST_NEWER_GLIBC:-0}" = 1 ]; then
  echo '  Name: GLIBC_2.44  Flags: none  Version: 2'
  exit 0
fi
exec /usr/bin/readelf "$@"
READELF
chmod +x "$T/fake-bin/readelf"
set +e
FIRE4NIX_TEST_FAKE_GST=1 FIRE4NIX_REQUIRE_MEDIA_FREE=1 PATH="$T/fake-bin:$PATH" \
 FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/unsafe-media" \
 sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/unsafe-media.log" 2>&1
media_rc=$?
set -e
test "$media_rc" -eq 5
grep -q 'media-free build still links GStreamer' "$T/unsafe-media.log"
test ! -e "$T/unsafe-media"
echo 'PASS: ELF/glibc and media-free dependency guards reject unsafe staging (mock only)'
