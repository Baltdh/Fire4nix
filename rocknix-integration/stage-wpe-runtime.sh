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
command -v readelf >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 || {
  echo 'ERROR: readelf and sha256sum required for AArch64 verification' >&2
  exit 2
}
# Prevent accidental copying of the build host's /usr into a browser package.
case "$INPUT" in
  /|/usr|/usr/|/usr/local|/usr/local/|.) echo 'ERROR: unsafe input directory' >&2; exit 2 ;;
esac
case "$OUT" in
  /|/usr|/usr/*) echo 'ERROR: unsafe runtime output path' >&2; exit 2 ;;
esac
[ ! -e "$OUT" ] || { echo 'ERROR: output already exists; never overwrite a WPE runtime' >&2; exit 2; }
LIBROOT=
for p in "$INPUT/usr/lib" "$INPUT/usr/lib64"; do
  if [ -s "$p/libWPEWebKit-2.0.so.1" ]; then LIBROOT="$p"; break; fi
done
[ -n "$LIBROOT" ] || { echo 'ERROR: staged WPE library/SONAME missing' >&2; exit 3; }
CHILDROOT=
for p in "$INPUT/usr/libexec/wpe-webkit-2.0" "$INPUT/usr/lib/wpe-webkit-2.0"; do
  if [ -d "$p" ]; then CHILDROOT="$p"; break; fi
done
[ -n "$CHILDROOT" ] || { echo 'ERROR: staged WPE subprocess directory missing' >&2; exit 3; }
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  [ -s "$CHILDROOT/$p" ] || { echo "ERROR: missing staged $p" >&2; exit 3; }
done
check_arm64() {
  readelf -h "$1" 2>/dev/null | grep -q 'Machine:.*AArch64' || {
    echo "ERROR: non-AArch64 or non-ELF file: $(basename "$1")" >&2
    return 1
  }
}
check_arm64 "$LIBROOT/libWPEWebKit-2.0.so.1" || exit 4
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  check_arm64 "$CHILDROOT/$p" || exit 4
done
if ! readelf --dyn-syms -W "$LIBROOT/libWPEWebKit-2.0.so.1" | grep -q 'webkit_web_view_get_wpe_view'; then
  echo 'ERROR: library has no WPEPlatform webkit_web_view_get_wpe_view symbol' >&2
  exit 5
fi
PARENT=$(dirname "$OUT")
mkdir -p "$PARENT"
TEMP=$(mktemp -d "$PARENT/.fire4nix-stage-wpe-XXXXXXXX") || exit 6
cleanup() { status=$?; trap - 0; [ ! -d "$TEMP" ] || rm -rf "$TEMP"; exit "$status"; }
trap cleanup 0
mkdir -p "$TEMP/lib" "$TEMP/libexec/wpe-webkit-2.0"
# DESTDIR is expected to contain only this WPE install, not an OS sysroot.
for lib in "$LIBROOT/"*.so "$LIBROOT/"*.so.*; do
  [ -e "$lib" ] || [ -L "$lib" ] || continue
  cp -a "$lib" "$TEMP/lib/"
done
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  cp -a "$CHILDROOT/$p" "$TEMP/libexec/wpe-webkit-2.0/$p"
done
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
   libexec/wpe-webkit-2.0/WPEGPUProcess; do
    sha256sum "$p"
  done > SHA256SUMS.txt
)
# Document unresolved target link dependencies without falsely asserting that
# they are available; final validation requires the actual ROCKNIX rootfs.
{
  echo 'Fire4Nix WPE runtime staged from ROCKNIX SDK DESTDIR.'
  echo 'AArch64 ELF and WPEPlatform exported symbol checked.'
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
