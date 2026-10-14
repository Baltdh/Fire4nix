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
   "$script_dir/Fire4Nix" \
   "$script_dir/navegador-definitivo" \
   "$script_dir/../Fire4Nix" \
   "$script_dir/../navegador-definitivo" \
   /storage/games-internal/roms/tools/Fire4Nix \
   /storage/games-internal/roms/tools/navegador-definitivo \
   /storage/games-external/roms/tools/Fire4Nix \
   /storage/roms/tools/Fire4Nix \
   /storage/roms/Tools/Fire4Nix \
   /storage/roms/ports/Fire4Nix \
   "$script_dir"; do
   # A Tools-root Fire4Nix.sh may be the launcher, not the browser.
   # Prefer the actual application directory with scripts/run_browser.sh.
   if [ -f "$candidate/Fire4Nix.sh" ] && [ -f "$candidate/scripts/run_browser.sh" ]; then
     (CDPATH='' cd -- "$candidate" && pwd -P)
     return 0
   fi
 done
 printf '%s\n' "$script_dir/Fire4Nix"
}
run_diagnostic() {
APP="$(find_app_for_diagnostic)"
echo "=== Fire4Nix WPE preflight ==="
echo "checked_at: $(date 2>/dev/null || printf unknown)"
echo "kernel: $(uname -r 2>/dev/null || printf unknown)"
echo "architecture: $(uname -m)"
echo "app: $APP"
echo "tools_script: $0"
if [ -f "$APP/scripts/run_browser.sh" ]; then
 echo "app scripts/run_browser.sh: OK"
else
 echo "app scripts/run_browser.sh: MISSING (launcher-only or incomplete application)"
fi
if [ -f "$APP/bin/fire4nix-wpe-platform" ]; then
 echo "native WPE engine: present"
else
 echo "native WPE engine: MISSING"
fi
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
# Compare C++ ABI independently from glibc. This is read-only.
DEVICE_LIBSTDCPP="${FIRE4NIX_DEVICE_LIBSTDCPP:-}"
for cpp_path in \
 /usr/lib/libstdc++.so.6 /usr/lib64/libstdc++.so.6 \
 /lib/libstdc++.so.6 /lib64/libstdc++.so.6 \
 /usr/lib/aarch64-linux-gnu/libstdc++.so.6 \
 /usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
 /lib/aarch64-linux-gnu/libstdc++.so.6; do
 if [ -n "$DEVICE_LIBSTDCPP" ]; then break; fi
 if [ -f "$cpp_path" ]; then DEVICE_LIBSTDCPP="$cpp_path"; break; fi
done
if [ -n "$DEVICE_LIBSTDCPP" ] && [ ! -f "$DEVICE_LIBSTDCPP" ]; then
 echo "WARNING: requested device libstdc++ provider does not exist: $DEVICE_LIBSTDCPP"
 DEVICE_LIBSTDCPP=""
fi
echo "Device libstdc++ provider: ${DEVICE_LIBSTDCPP:-not found}"
check_cpp_abi_version() {
 family=$1
 requirement=$2
 if [ -z "$DEVICE_LIBSTDCPP" ] || ! command -v readelf >/dev/null 2>&1; then
  echo "WPE $family compatibility: unverified (no device libstdc++ or readelf)"
  return 0
 fi
 available="$(readelf --version-info "$DEVICE_LIBSTDCPP" 2>/dev/null |
  grep -Eo "${family}_[0-9]+([.][0-9]+)+" |
  awk -F_ '{print $2}' | sort -u |
  awk -F. '{
    a=$1+0; b=$2+0; c=$3+0; d=$4+0;
    if (NR==1 || a>aa || (a==aa && b>bb) ||
        (a==aa && b==bb && c>cc) ||
        (a==aa && b==bb && c==cc && d>dd)) {
      aa=a; bb=b; cc=c; dd=d; best=$0
    }
  } END {print best}' || true)"
 if [ -z "$available" ]; then
  echo "WPE $family compatibility: unverified (no $family versions found)"
  return 0
 fi
 echo "Device highest $family: ${family}_$available"
 if awk -v need="${requirement#*_}" -v host="$available" 'BEGIN {
   split(need,n,"."); split(host,h,".");
   for (i=1; i<=4; i++) {
     if ((n[i]+0)>(h[i]+0)) exit 1
     if ((n[i]+0)<(h[i]+0)) exit 0
   }
   exit 0
 }'; then
  echo "WPE $family requirement: satisfied (other dependencies unverified)"
 else
  echo "INCOMPATIBLE: WPE build requires $requirement but device libstdc++ supports up to ${family}_$available"
 fi
}
for manifest in "$APP/../WPE-ABI-REQUIREMENTS.json" "$APP/WPE-ABI-REQUIREMENTS.json"; do
 if [ -f "$manifest" ]; then
  echo "WPE ABI manifest supplied: $manifest"
  # Informational JSON data, not executable; parse the known GLIBC field.
  # This does not require jq or Python to be installed on ROCKNIX.
  wpe_floor="$(sed -n 's/.*"highest_required_glibc_across_components":[[:space:]]*"\(GLIBC_[0-9.]*\)".*/\1/p' "$manifest" 2>/dev/null | head -1)"
  echo "WPE build-origin GLIBC floor: ${wpe_floor:-unavailable}"
  for abi_family in GLIBCXX CXXABI; do
   abi_version="$(sed -n "s/.*\"$abi_family\":[[:space:]]*\"\([A-Z0-9_.]*\)\".*/\1/p" "$manifest" 2>/dev/null | head -1)"
   echo "WPE build-origin $abi_family requirement: ${abi_version:-unavailable}"
   if [ -n "$abi_version" ]; then check_cpp_abi_version "$abi_family" "$abi_version"; fi
  done
  case "$LIBC_VERSION" in
   "glibc "[0-9]*)
    if [ -n "$wpe_floor" ]; then
     if awk -v need="${wpe_floor#GLIBC_}" -v host="${LIBC_VERSION#glibc }" 'BEGIN {
       split(need,n,"."); split(host,h,".");
       for (i=1; i<=3; i++) {
         a=n[i]+0; b=h[i]+0;
         if (a>b) exit 1;
         if (a<b) exit 0;
       }
       exit 0
     }'; then
      echo "WPE build GLIBC requirement: satisfied (other runtime dependencies unverified)"
     else
      echo "INCOMPATIBLE: WPE build requires $wpe_floor but device reports $LIBC_VERSION"
     fi
    fi
    ;;
   *) echo "WPE build GLIBC comparison: unavailable" ;;
  esac
  echo "WPE ABI validation: device libraries, dynamic modules and graphics unverified"
  break
 fi
done
for cmd in bash cog bwrap file readelf ldd pkg-config timeout; do
 if command -v "$cmd" >/dev/null 2>&1; then
   echo "command $cmd: $(command -v "$cmd")"
 else
   echo "command $cmd: MISSING"
 fi
done
echo "WPE sandbox prerequisites:"
if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
 echo "kernel.unprivileged_userns_clone: $(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo unknown)"
else
 echo "kernel.unprivileged_userns_clone: unavailable"
fi
if [ -f /proc/sys/user/max_user_namespaces ]; then
 echo "user.max_user_namespaces: $(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo unknown)"
fi
if command -v bwrap >/dev/null 2>&1; then
 # This launches only a no-op shell under read-only binds, never the browser.
 # Keep it time-limited on devices providing the standard timeout utility.
 if command -v timeout >/dev/null 2>&1; then
  timeout 5s bwrap --unshare-user --ro-bind / / -- /bin/sh -c ':' >/dev/null 2>&1
  sandbox_status=$?
 else
  bwrap --unshare-user --ro-bind / / -- /bin/sh -c ':' >/dev/null 2>&1
  sandbox_status=$?
 fi
 if [ "$sandbox_status" -eq 0 ]; then
  echo "WPE Bubblewrap namespace preflight: PASS (not proof of full sandbox)"
 else
  echo "WPE Bubblewrap namespace preflight: FAIL (exit $sandbox_status)"
  echo "WARNING: sandboxed WebKit subprocess startup remains unverified"
 fi
else
 echo "WPE Bubblewrap namespace preflight: UNAVAILABLE (bwrap not found)"
 echo "WARNING: sandboxed WebKit subprocess startup remains unverified"
fi
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
   check_elf_abi "$f"
 fi
 if command -v ldd >/dev/null 2>&1 && [ -x "$f" ]; then
   dependencies="$(ldd "$f" 2>&1 || true)"
   case "$dependencies" in
     *'not found'*) echo "WARNING: unresolved shared libraries for $f"; printf '%s\n' "$dependencies" | grep 'not found' ;;
   esac
 fi
done
# Report the Debian build's direct ELF NEEDED library names. This does
# not modify LD_LIBRARY_PATH or try to load a foreign binary on ROCKNIX.
NEEDED_FILE="$APP/../WPE-CORE-NEEDED.txt"
NEEDED_SCOPE="direct"
if [ -f "$APP/../WPE-CORE-ALL-NEEDED.txt" ]; then
 NEEDED_FILE="$APP/../WPE-CORE-ALL-NEEDED.txt"
 NEEDED_SCOPE="direct and transitive"
fi
if [ -f "$NEEDED_FILE" ]; then
 echo "WPE Core external $NEEDED_SCOPE dependencies (build-origin; lookup in common ROCKNIX paths):"
 LINKER_CACHE=""
 if command -v ldconfig >/dev/null 2>&1; then
  LINKER_CACHE="$(ldconfig -p 2>/dev/null || true)"
 fi
 unresolved=0
 while IFS= read -r soname || [ -n "$soname" ]; do
  # Do not interpret an arbitrary package metadata value as a shell path.
  case "$soname" in
   ''|*[!A-Za-z0-9._+-]*)
    echo "WARNING: invalid WPE dependency SONAME in metadata"
    continue
    ;;
  esac
  library_found=""
  for library_dir in \
    /usr/lib /lib /usr/lib64 /lib64 /usr/local/lib \
    /usr/lib/aarch64-linux-gnu /lib/aarch64-linux-gnu; do
   if [ -f "$library_dir/$soname" ]; then
    library_found="$library_dir/$soname"
    break
   fi
  done
  if [ -n "$library_found" ]; then
   echo "$soname: found $library_found"
  elif [ -n "$LINKER_CACHE" ] && printf '%s\n' "$LINKER_CACHE" | grep -Fq "$soname ("; then
   echo "$soname: listed by ldconfig (loader resolution not verified)"
  else
   echo "$soname: NOT FOUND in common paths (other paths may exist)"
   unresolved=$((unresolved + 1))
  fi
 done < "$NEEDED_FILE"
 echo "WPE Core $NEEDED_SCOPE SONAMEs not located in common paths: $unresolved"
 echo "NOTE: this does not prove loader ABI compatibility or detect dlopen plugins"
fi
echo "WPE subprocess inventory (system paths):"
for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
 found=""
 for root in /usr/libexec/wpe-webkit-2.0 /usr/local/libexec/wpe-webkit-2.0 /usr/lib/wpe-webkit-2.0 /storage/usr/libexec/wpe-webkit-2.0; do
  if [ -f "$root/$process" ]; then found="$root/$process"; break; fi
 done
 if [ -n "$found" ]; then
  echo "$process: $found"
 else
  echo "$process: NOT FOUND at known WPE runtime paths"
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
