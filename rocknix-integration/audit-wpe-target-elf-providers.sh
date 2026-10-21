#!/bin/sh
# Read-only link-provider audit for a ROCKNIX AArch64 WPE cross-build sysroot.
# pkg-config metadata is NOT proof that its linked libraries exist or are ARM64.
set -eu
mode=${1:---inspect}
case "$mode" in --inspect|--strict) ;; --help)
  echo 'FIRE4NIX_ROCKNIX_SYSROOT=/absolute/sysroot sh audit-wpe-target-elf-providers.sh --inspect|--strict'; exit 0 ;;
  *) echo 'ERROR: use --inspect or --strict' >&2; exit 2 ;;
esac
root=${FIRE4NIX_ROCKNIX_SYSROOT:-}
case "$root" in /*) [ -d "$root" ] || exit 4 ;; *) echo 'ERROR: absolute target sysroot required' >&2; exit 4 ;; esac
root=$(CDPATH= cd -- "$root" && pwd -P)
case "$root" in /|/usr|/usr/*|/lib|/lib/*|/storage|/storage/*)
  echo 'ERROR: refusing system paths instead of cross-build sysroot' >&2; exit 4 ;;
esac
case "$root" in *' '*|*':'*) echo 'ERROR: sysroot paths with spaces/colons unsupported' >&2; exit 4 ;; esac
for tool in pkg-config readelf readlink awk grep sort; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing build-host tool $tool" >&2; exit 4; }
done
release=${FIRE4NIX_ROCKNIX_RELEASE:-20260801}
case "$release" in 20260801) max=2.41 ;; 20261001) max=2.44 ;;
  *) echo 'ERROR: unverified target ROCKNIX release' >&2; exit 4 ;;
esac
pcdirs=
for rel in usr/lib/pkgconfig usr/lib64/pkgconfig usr/share/pkgconfig \
  usr/lib/aarch64-linux-gnu/pkgconfig lib/pkgconfig lib64/pkgconfig \
  lib/aarch64-linux-gnu/pkgconfig; do
  if [ -d "$root/$rel" ]; then pcdirs=${pcdirs:+$pcdirs:}$root/$rel; fi
done
[ -n "$pcdirs" ] || { echo 'TARGET_ELF_AUDIT=BLOCKED_NO_TARGET_PC_DIRS'; exit 6; }
export PKG_CONFIG_LIBDIR="$pcdirs" PKG_CONFIG_SYSROOT_DIR="$root" PKG_CONFIG_PATH=''
unset PKG_CONFIG_TOP_BUILD_DIR PKG_CONFIG_SYSTEM_LIBRARY_PATH PKG_CONFIG_SYSTEM_INCLUDE_PATH || true
failures=0
providers=0
report_failure() { echo "TARGET_LINK_BLOCKED=$1"; failures=$((failures+1)); }
# Check the first candidate: an invalid .so earlier in a linker's search list
# must not be silently skipped in favor of a valid file in a later directory.
check_elf() {
  p=$1
  [ -f "$p" ] || { report_failure "NOT_REGULAR_FILE:$p"; return 1; }
  real=$(readlink -f "$p") || { report_failure "UNRESOLVED_SYMLINK:$p"; return 1; }
  case "$real" in "$root"/*) ;; *) report_failure "HOST_OR_OUTSIDE_SYSROOT:$p"; return 1 ;; esac
  header=$(readelf -h "$real" 2>/dev/null) || { report_failure "INVALID_ELF:$p"; return 1; }
  printf '%s\n' "$header" | grep -q 'Class:.*ELF64' || { report_failure "NOT_ELF64:$p"; return 1; }
  printf '%s\n' "$header" | grep -q 'Machine:.*AArch64' || { report_failure "NOT_AARCH64:$p"; return 1; }
  printf '%s\n' "$header" | grep -q 'Type:.*DYN' || { report_failure "NOT_SHARED_LIBRARY:$p"; return 1; }
  required=$(readelf -V "$real" 2>/dev/null | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' | sed 's/Name: GLIBC_//' | sort -Vu | tail -n 1 || true)
  if [ -n "$required" ] && ! awk -v v="$required" -v m="$max" 'BEGIN {split(v,a,".");split(m,b,"."); exit !(a[1]<b[1]||(a[1]==b[1]&&a[2]<=b[2]))}'; then
    report_failure "GLIBC_TOO_NEW:$p:required=$required:max=$max"
    return 1
  fi
  if readelf -d "$real" 2>/dev/null | grep -Eq 'Shared library: \[libgst[^]]*\]'; then
    report_failure "GSTREAMER_DIRECT_NEEDED_IN_MEDIA_FREE:$p"
    return 1
  fi
  providers=$((providers+1))
  echo "TARGET_LINK_ELF_OK=$p"
}
# Metadata must be resolved only from the target SDK. The first provider is
# checked by its exact -L order, followed by conservative target default dirs.
for pc in glib-2.0 gio-2.0 libsoup-3.0 libtasn1 harfbuzz epoxy wayland-client; do
  if ! pkg-config --exists "$pc" 2>/dev/null; then
    report_failure "MISSING_PC:$pc"
    continue
  fi
  origin=$(pkg-config --variable=pcfiledir "$pc" 2>/dev/null || true)
  case "$origin" in "$root"/*) ;; *) report_failure "HOST_PC:$pc:$origin"; continue ;; esac
  flags=$(pkg-config --libs "$pc" 2>/dev/null) || { report_failure "INVALID_PC_LIBS:$pc"; continue; }
  searchdirs=
  set -f
  for flag in $flags; do
    case "$flag" in
      -L*)
        dir=${flag#-L}
        case "$dir" in "$root"/*) searchdirs="$searchdirs $dir" ;;
          *) report_failure "HOST_LINK_SEARCH_PATH:$pc:$dir" ;;
        esac ;;
      -Wl,*rpath*|-Wl,*Rpath*) report_failure "RPATH_IN_PC:$pc:$flag" ;;
    esac
  done
  for flag in $flags; do
    case "$flag" in
      -l*)
        soname=lib${flag#-l}.so
        selected=
        for dir in $searchdirs "$root/usr/lib" "$root/usr/lib64" \
          "$root/lib" "$root/lib64" "$root/usr/lib/aarch64-linux-gnu" \
          "$root/lib/aarch64-linux-gnu"; do
          if [ -e "$dir/$soname" ] || [ -L "$dir/$soname" ]; then
            selected="$dir/$soname"; break
          fi
        done
        if [ -z "$selected" ]; then report_failure "MISSING_PROVIDER:$pc:$soname"
        else check_elf "$selected" || true; fi ;;
    esac
  done
  set +f
done
# glib-networking exposes a GIO module, not a glib-networking.pc file.
# A build without giognutls.so may render HTTP but cannot establish HTTPS.
tls=
for path in usr/lib/gio/modules/libgiognutls.so usr/lib64/gio/modules/libgiognutls.so \
  usr/lib/glib-2.0/gio/modules/libgiognutls.so usr/lib64/glib-2.0/gio/modules/libgiognutls.so; do
  if [ -e "$root/$path" ] || [ -L "$root/$path" ]; then tls="$root/$path"; break; fi
done
if [ -z "$tls" ]; then report_failure 'MISSING_GIO_GNUTLS_MODULE:HTTPS_NOT_READY'
else check_elf "$tls" || true; fi
echo "TARGET_LINK_PROVIDERS_CHECKED=$providers"
echo "TARGET_LINK_FAILURES=$failures"
echo 'CA_TRUST_STORE=REQUIRES_PHYSICAL_ROCKNIX_RUNTIME_VERIFICATION'
echo 'LIMITATION=STATIC_ELF_PROVIDER_CHECK_NOT_COMPLETE_SYMBOL_RESOLUTION_OR_HTTPS_TEST'
if [ "$failures" -eq 0 ]; then
  echo 'TARGET_ELF_AUDIT=PASS_STATIC_AARCH64_PROVIDERS_TLS_MODULE'
else
  echo 'TARGET_ELF_AUDIT=BLOCKED_INCOMPLETE_OR_INCOMPATIBLE_TARGET_DEPENDENCIES'
fi
[ "$mode" != --strict ] || [ "$failures" -eq 0 ] || exit 6
