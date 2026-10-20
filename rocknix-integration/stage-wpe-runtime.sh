#!/bin/sh
# Stage WPE from a ROCKNIX-built DESTDIR, NEVER from the build host's /usr.
# Output only when all ARM64 ABI and subprocess checks pass. No network/root.
set -eu
MODE=${1:---help}
case "$MODE" in --help|--stage) ;; *) echo 'Usage: stage-wpe-runtime.sh --stage' >&2; exit 2 ;; esac
if [ "$MODE" = "--help" ]; then
  echo 'Stage WebKit WPEPlatform runtime from an isolated ROCKNIX AArch64 DESTDIR.'
  echo 'Required: FIRE4NIX_WPE_DESTDIR=/path/to/staged/root'
  echo '          FIRE4NIX_WPE_RUNTIME_OUT=/path/to/new/runtime'
  echo 'Example: FIRE4NIX_WPE_DESTDIR=... FIRE4NIX_WPE_RUNTIME_OUT=... sh stage-wpe-runtime.sh --stage'
  exit 0
fi
INPUT=${FIRE4NIX_WPE_DESTDIR:-}
OUT=${FIRE4NIX_WPE_RUNTIME_OUT:-}
[ -n "$INPUT" ] && [ -d "$INPUT" ] && [ -n "$OUT" ] || {
  echo 'ERROR: explicit ROCKNIX WPE DESTDIR and runtime output are required' >&2
  exit 2
}
command -v readelf >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 && command -v sort >/dev/null 2>&1 || {
  echo 'ERROR: readelf and sha256sum required for AArch64 verification' >&2
  exit 2
}
# The current physical R36H reports glibc 2.41, so reject newer symbols.
# Explicit opt-in for other firmware only after independently auditing its rootfs.
TARGET_GLIBC_MAX=${FIRE4NIX_TARGET_GLIBC_MAX:-2.41}
case "$TARGET_GLIBC_MAX" in 2.41|2.44) ;; *) echo 'ERROR: unsupported target glibc; audit the actual rootfs first' >&2; exit 2 ;; esac
# Prevent accidental copying of the build host's /usr into a browser package.
case "$INPUT" in
  /|/usr|/usr/|/usr/local|/usr/local/|.) echo 'ERROR: unsafe input directory' >&2; exit 2 ;;
esac
case "$OUT" in
  /|/usr|/usr/*) echo 'ERROR: unsafe runtime output path' >&2; exit 2 ;;
esac
# -e is false for a dangling symlink. Refuse it as well: stage never
# replaces even an incomplete output path or symlink.
{ [ ! -e "$OUT" ] && [ ! -L "$OUT" ]; } || {
  echo 'ERROR: output already exists; never overwrite a WPE runtime' >&2
  exit 2
}
LIBROOT=
for p in "$INPUT/usr/lib" "$INPUT/usr/lib64"; do
  if [ -s "$p/libWPEWebKit-2.0.so.1" ]; then LIBROOT="$p"; break; fi
done
[ -n "$LIBROOT" ] || { echo 'ERROR: staged WPE library/SONAME missing' >&2; exit 3; }
CHILDROOT=
for p in "$INPUT/usr/libexec/wpe-webkit-2.0" "$LIBROOT/wpe-webkit-2.0" "$INPUT/usr/lib/wpe-webkit-2.0"; do
  if [ -d "$p" ]; then CHILDROOT="$p"; break; fi
done
[ -n "$CHILDROOT" ] || { echo 'ERROR: staged WPE subprocess directory missing' >&2; exit 3; }
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  [ -s "$CHILDROOT/$p" ] || { echo "ERROR: missing staged $p" >&2; exit 3; }
done
# WPE 2.54 installs an injected bundle and inspector data in nested paths.
# The previous stager silently dropped both, producing an incomplete runtime.
BUNDLEROOT="$LIBROOT/wpe-webkit-2.0/injected-bundle"
RESOURCE_ROOT="$INPUT/usr/share/wpe-webkit-2.0"
[ -s "$BUNDLEROOT/libWPEInjectedBundle.so" ] || {
  echo 'ERROR: staged WPE injected bundle missing' >&2; exit 3;
}
[ -s "$RESOURCE_ROOT/inspector.gresource" ] || {
  echo 'ERROR: staged WPE inspector.gresource missing' >&2; exit 3;
}
check_arm64() {
  readelf -h "$1" 2>/dev/null | grep -q 'Machine:.*AArch64' || {
    echo "ERROR: non-AArch64 or non-ELF file: $(basename "$1")" >&2
    return 1
  }
}
# This scans version requirements, not merely the ELF machine type. It cannot
# prove that the ROCKNIX rootfs provides every transitive dependency.
check_glibc_max() {
  required=$(readelf -V "$1" 2>/dev/null | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' | sed 's/Name: GLIBC_//' | sort -Vu | tail -n 1 || true)
  [ -n "$required" ] || return 0
  if ! awk -v required="$required" -v max="$TARGET_GLIBC_MAX" 'BEGIN {
       split(required, r, "."); split(max, m, ".");
       exit !(r[1] < m[1] || (r[1] == m[1] && r[2] <= m[2]))
     }'; then
    echo "ERROR: $(basename "$1") needs GLIBC_$required; device limit is GLIBC_$TARGET_GLIBC_MAX" >&2
    return 1
  fi
}
check_arm64 "$LIBROOT/libWPEWebKit-2.0.so.1" || exit 4
check_glibc_max "$LIBROOT/libWPEWebKit-2.0.so.1" || exit 4
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  check_arm64 "$CHILDROOT/$p" || exit 4
  check_glibc_max "$CHILDROOT/$p" || exit 4
done
check_arm64 "$BUNDLEROOT/libWPEInjectedBundle.so" || exit 4
check_glibc_max "$BUNDLEROOT/libWPEInjectedBundle.so" || exit 4
if ! readelf --dyn-syms -W "$LIBROOT/libWPEWebKit-2.0.so.1" | grep -q 'webkit_web_view_get_wpe_view'; then
  echo 'ERROR: library has no WPEPlatform webkit_web_view_get_wpe_view symbol' >&2
  exit 5
fi
PARENT=$(dirname "$OUT")
mkdir -p "$PARENT"
TEMP=$(mktemp -d "$PARENT/.fire4nix-stage-wpe-XXXXXXXX") || exit 6
cleanup() { status=$?; trap - 0; [ ! -d "$TEMP" ] || rm -rf "$TEMP"; exit "$status"; }
trap cleanup 0
mkdir -p "$TEMP/lib" "$TEMP/libexec/wpe-webkit-2.0" \
  "$TEMP/lib/wpe-webkit-2.0/injected-bundle" "$TEMP/share/wpe-webkit-2.0"
# DESTDIR is expected to contain only this WPE install, not an OS sysroot.
for lib in "$LIBROOT/"*.so "$LIBROOT/"*.so.*; do
  [ -e "$lib" ] || [ -L "$lib" ] || continue
  if [ ! -L "$lib" ]; then
    check_arm64 "$lib" || exit 4
    check_glibc_max "$lib" || exit 4
  fi
  cp -a "$lib" "$TEMP/lib/"
done
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  cp -a "$CHILDROOT/$p" "$TEMP/libexec/wpe-webkit-2.0/$p"
done
# Preserve the upstream installation's injected bundle and all bundled
# WPE data (inspector, localized resources if present), never the host's /usr.
cp -a "$BUNDLEROOT/." "$TEMP/lib/wpe-webkit-2.0/injected-bundle/"
cp -a "$RESOURCE_ROOT/." "$TEMP/share/wpe-webkit-2.0/"
for bundle in "$TEMP/lib/wpe-webkit-2.0/injected-bundle/"*.so*; do
  [ -e "$bundle" ] || [ -L "$bundle" ] || continue
  [ -L "$bundle" ] && continue
  check_arm64 "$bundle" || exit 4
  check_glibc_max "$bundle" || exit 4
done
# Reject broken GStreamer ELF before committing a runtime. The R36H rescue
# package showed GST_CAT_DEFAULT as undefined in six gst* libraries, and
# the target system's libgstreamer does not export it. This is a static guard;
# external dependencies still need target-rootfs testing.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
AUDITOR="$SCRIPT_DIR/audit-wpe-gstreamer.sh"
[ -f "$AUDITOR" ] || { echo 'ERROR: GStreamer ABI auditor missing alongside staging script' >&2; exit 5; }
if ! FIRE4NIX_GST_REPORT="$TEMP/GSTREAMER-ABI-REPORT.txt" sh "$AUDITOR" --strict "$TEMP" >/dev/null; then
  cat "$TEMP/GSTREAMER-ABI-REPORT.txt" >&2
  echo 'ERROR: packaged GStreamer ELF has unresolved GST_CAT_DEFAULT; refuse runtime' >&2
  exit 5
fi
# The first browser profile is intentionally built with USE_GSTREAMER=OFF.
# Validate DT_NEEDED of all staged ELF, not just presence of libgst files.
# Profiles/flags can be ignored by a misconfigured SDK or stale build dir.
if [ "${FIRE4NIX_REQUIRE_MEDIA_FREE:-0}" = 1 ]; then
  for media_elf in "$TEMP/lib/"*.so "$TEMP/lib/"*.so.* \
       "$TEMP/libexec/wpe-webkit-2.0/"* \
       "$TEMP/lib/wpe-webkit-2.0/injected-bundle/"*.so*; do
    [ -f "$media_elf" ] || continue
    [ -L "$media_elf" ] && continue
    if readelf -d "$media_elf" 2>/dev/null | grep -E 'Shared library: \[libgst[^]]*\]' >/dev/null; then
      echo "ERROR: media-free build still links GStreamer: $(basename "$media_elf")" >&2
      exit 5
    fi
  done
  echo 'PROFILE=MEDIA_FREE VERIFIED' > "$TEMP/MEDIA-PROFILE.txt"
fi
# Refuse broken or external SONAME links. Symlinks must resolve within lib.
for lib in "$TEMP/lib/"*.so*; do
  [ -L "$lib" ] || continue
  target=$(readlink "$lib")
  case "$target" in /*|*..*) echo 'ERROR: unsafe or external shared-library symlink' >&2; exit 5 ;; esac
  [ -e "$TEMP/lib/$target" ] || { echo 'ERROR: broken shared library link' >&2; exit 5; }
done
(
  cd "$TEMP"
  for p in lib/libWPEWebKit-2.0.so.1 \
   libexec/wpe-webkit-2.0/WPEWebProcess \
   libexec/wpe-webkit-2.0/WPENetworkProcess \
   libexec/wpe-webkit-2.0/WPEGPUProcess \
   lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so \
   share/wpe-webkit-2.0/inspector.gresource; do
    sha256sum "$p"
  done > SHA256SUMS.txt
)
# Document unresolved target link dependencies without falsely asserting that
# they are available; final validation requires the actual ROCKNIX rootfs.
{
  echo 'Fire4Nix WPE runtime staged from ROCKNIX SDK DESTDIR.'
  echo 'AArch64 ELF and WPEPlatform exported symbol checked.'
  echo 'Injected bundle and wpe-webkit-2.0 inspector resources staged and hashed.'
  echo "Max allowed direct GLIBC requirement: GLIBC_$TARGET_GLIBC_MAX"
  echo 'Dynamic dependencies must still be validated against the exact target rootfs.'
  echo 'Graphical startup and Mali/Wayland have NOT been tested here.'
  for p in "$TEMP/lib/libWPEWebKit-2.0.so.1" "$TEMP/libexec/wpe-webkit-2.0/WPEWebProcess"; do
    echo "NEEDED for $(basename "$p"):"
    readelf -d "$p" 2>/dev/null | grep '(NEEDED)' || true
  done
} > "$TEMP/BUILD-REPORT.txt"
# -T avoids overwriting a preexisting directory.
mv -T "$TEMP" "$OUT" || exit 6
echo "STAGED_RUNTIME=$OUT"
echo 'STATUS=ELF_VERIFIED_DEPENDENCIES_AND_REAL_WAYLAND_UNTESTED'
