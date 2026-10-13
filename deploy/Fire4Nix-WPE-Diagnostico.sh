#!/bin/sh
# Run on ROCKNIX: read-only checks, then save one private diagnostic log.
# Does not install packages, change graphics drivers, or disable the WebKit sandbox.
set -u
find_app_for_diagnostic() {
 if [ -n "${FIRE4NIX_APP_DIR:-}" ]; then
   printf '%s\n' "$FIRE4NIX_APP_DIR"
   return 0
 fi
 script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || script_dir=.
 for candidate in \
   "$script_dir" \
   "$script_dir/Fire4Nix" \
   "$script_dir/navegador-definitivo" \
   "$script_dir/../Fire4Nix" \
   "$script_dir/../navegador-definitivo" \
   /storage/roms/tools/Fire4Nix \
   /storage/roms/Tools/Fire4Nix \
   /storage/roms/ports/Fire4Nix; do
   if [ -f "$candidate/Fire4Nix.sh" ]; then
     (CDPATH='' cd -- "$candidate" && pwd -P)
     return 0
   fi
 done
 printf '%s\n' /storage/roms/ports/Fire4Nix
}
run_diagnostic() {
APP="$(find_app_for_diagnostic)"
echo "=== Fire4Nix WPE preflight ==="
echo "checked_at: $(date 2>/dev/null || printf unknown)"
echo "kernel: $(uname -r 2>/dev/null || printf unknown)"
echo "architecture: $(uname -m)"
echo "app: $APP"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
echo "WPE_PLATFORM=${WPE_PLATFORM:-auto}"
echo "WPE_DISPLAY=${WPE_DISPLAY:-unset (legacy)}"
echo "FIRE4NIX_WPE_DISPLAY=${FIRE4NIX_WPE_DISPLAY:-auto}"
LIBC_VERSION=""
if command -v getconf >/dev/null 2>&1; then
 LIBC_VERSION="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
fi
echo "libc: ${LIBC_VERSION:-unknown}"

check_elf_abi() {
 binary=$1
 command -v readelf >/dev/null 2>&1 || {
  echo "ABI: readelf unavailable; requirements unverified"
  return 0
 }
 echo "ELF interpreter:"
 readelf -l "$binary" 2>/dev/null | grep -F 'Requesting program interpreter:' || true
 echo "Required GLIBC versions:"
 versions="$(readelf --version-info "$binary" 2>/dev/null | grep -Eo 'GLIBC_[0-9]+([.][0-9]+)+' | sort -u || true)"
 if [ -z "$versions" ]; then
  echo "ABI: no GLIBC version requirements detected (not proof of compatibility)"
  return 0
 fi
 printf '%s\n' "$versions" | tr '\n' ' '
 printf '\n'
 maximum="$(printf '%s\n' "$versions" | awk -F '[_.]' '
   { maj=$2+0; min=$3+0; patch=$4+0;
     if (NR==1 || maj>bestmaj || (maj==bestmaj && min>bestmin) ||
         (maj==bestmaj && min==bestmin && patch>bestpatch)) {
       bestmaj=maj; bestmin=min; bestpatch=patch; best=$0
     }
   } END { print best }
 ')"
 echo "Highest required GLIBC: $maximum"
 case "$LIBC_VERSION" in
  "glibc "[0-9]*)
   host_version=${LIBC_VERSION#glibc }
   if printf '%s\n' "$host_version" | grep -Eq '^[0-9]+([.][0-9]+){1,2}$'; then
    if awk -v need="${maximum#GLIBC_}" -v host="$host_version" 'BEGIN {
      split(need,n,"."); split(host,h,".");
      for (i=1; i<=3; i++) {
        a=n[i]+0; b=h[i]+0;
        if (a>b) exit 1;
        if (a<b) exit 0;
      }
      exit 0
    }'; then
     echo "ABI GLIBC version floor: satisfied (other dependencies remain unverified)"
    else
     echo "INCOMPATIBLE: binary requires $maximum but device reports $LIBC_VERSION"
    fi
   fi
   ;;
  *) echo "ABI GLIBC comparison: unavailable (unknown/non-glibc libc)" ;;
 esac
}
for cmd in bash cog file readelf ldd pkg-config; do
 if command -v "$cmd" >/dev/null 2>&1; then
   echo "command $cmd: $(command -v "$cmd")"
 else
   echo "command $cmd: MISSING"
 fi
done
if [ ! -f "$APP/Fire4Nix.sh" ]; then
 echo "WARNING: no Fire4Nix.sh found at application path; put diagnostic beside the app or set FIRE4NIX_APP_DIR"
fi
for f in "$APP/fire4nix-wpe-platform" "$APP/bin/wpe-platform-launcher" "$APP/bin/wpe-platform" "$APP/build/fire4nix-wpe-platform" "$APP/bin/fire4nix-wpe-platform" "$APP/bin/browser.arm64"; do
 [ -f "$f" ] || continue
 echo "--- $f"
 if command -v file >/dev/null 2>&1; then file "$f"; else
   IFS= read -r first < "$f" || true
   case "$first" in '#!'*) echo "script: $first";; *) echo "type: unknown (file command unavailable)";; esac
 fi
 if command -v readelf >/dev/null 2>&1; then
   readelf -h "$f" 2>/dev/null | grep -E 'Class:|Machine:' || true
   readelf -d "$f" 2>/dev/null | grep NEEDED || true
 fi
 if command -v ldd >/dev/null 2>&1 && [ -x "$f" ]; then
   dependencies="$(ldd "$f" 2>&1 || true)"
   case "$dependencies" in
     *'not found'*) echo "WARNING: unresolved shared libraries for $f"; printf '%s\n' "$dependencies" | grep 'not found' ;;
   esac
 fi
done
for name in libWPEBackend-fdo-1.0.so libwpe-1.0.so libWPEWebKit-2.0.so libwebkit2gtk-4.1.so; do
 if command -v ldconfig >/dev/null 2>&1; then
   ldconfig -p 2>/dev/null | grep -F "$name" || true
 fi
done
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
 if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then echo "Wayland socket: OK"; else echo "Wayland socket: MISSING"; fi
else
 echo "Wayland socket: environment unavailable"
fi
echo "=== end ==="
}

# The R36H may close a Tools-launched shell immediately. Persist the report
# to a predictable location so it can be inspected later without a terminal.
REPORT="${FIRE4NIX_DIAGNOSTIC_LOG:-}"
if [ -z "$REPORT" ]; then
 if [ -d /storage ] && [ -w /storage ]; then
  REPORT="/storage/fire4nix-wpe-diagnostic.log"
 else
  REPORT="${TMPDIR:-/tmp}/fire4nix-wpe-diagnostic.log"
 fi
fi
if (umask 077; : > "$REPORT") 2>/dev/null; then
 run_diagnostic > "$REPORT" 2>&1
 cat "$REPORT"
 echo "Diagnostic saved: $REPORT"
else
 echo "WARNING: cannot save diagnostic at $REPORT; printing instead" >&2
 run_diagnostic
fi
