#!/usr/bin/env bash
# Fire4Nix first REAL native AArch64 build test (not a ROCKNIX SDK build).
# Compiles the four missing libraries on an isolated Ubuntu ARM64 GitHub runner.
# Never deploy these libraries to R36H: platform/glibc ABI validation is required.
set -euo pipefail
mode=${1:---plan}
case "$mode" in
  --plan|--build) ;;
  *) echo 'Usage: build-aarch64-dependencies-smoke.sh --plan|--build' >&2; exit 2 ;;
esac
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
lock="$repo/rocknix-integration/rocknix-wpe-prerequisites.lock"
[ -r "$lock" ] || { echo 'ERROR: lock file missing' >&2; exit 4; }
echo "build_mode=$mode"
echo "target=ARM64_NATIVE_UBUNTU_ONLY_NOT_ROCKNIX_SDK"
echo "source_lock=$lock"
echo "browser_compiled=no"
echo "firmware_modified=no"
if [ "$mode" = --plan ]; then
  echo 'plan=build_libtasn1_libpsl_glib_networking_libsoup3_then_offline_https_backend_smoke'
  exit 0
fi
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: requires native AArch64 runner, no x86 host fallback' >&2; exit 4; }
for exe in cc make meson ninja pkg-config curl sha256sum readelf tar; do
  command -v "$exe" >/dev/null || { echo "ERROR: missing $exe" >&2; exit 4; }
done
work=${FIRE4NIX_BUILD_WORK:-}
[ -n "$work" ] && [ -d "$work" ] || {
  echo 'ERROR: set FIRE4NIX_BUILD_WORK to a writable isolated temporary directory' >&2; exit 4
}
work=$(cd "$work" && pwd -P)
case "$work" in /|/usr|/usr/*|/storage|/storage/*) echo 'ERROR: unsafe work directory' >&2; exit 4;; esac
prefix="$work/arm64-prerequisites"
sources="$work/sources"
reports="$work/reports"
mkdir -p "$prefix" "$sources" "$reports"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$prefix/bin:$PATH"
export MAKEFLAGS='-j2'
echo "build_host_libc=$(getconf GNU_LIBC_VERSION)"
echo "build_host_arch=$(uname -m)"
# Fetch only explicit locked upstream source archives, independent of apt mirrors.
while IFS='|' read -r name sha url || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue;; esac
  case "$name" in libsoup3|libtasn1|glib-networking|libpsl) ;; *) exit 4;; esac
  case "$url" in https://*) ;; *) exit 4;; esac
  archive="$sources/$name.tar"
  echo "SOURCE_FETCH=$name"
  curl --fail --location --retry 3 --retry-delay 2 --proto '=https' --tlsv1.2 \
       --silent --show-error "$url" -o "$archive"
  printf '%s  %s\n' "$sha" "$archive" | sha256sum --check --status ||
    { echo "ERROR: SHA256 mismatch for $name" >&2; exit 5; }
  echo "SOURCE_SHA256=PASS:$name"
  mkdir -p "$sources/extract-$name"
  tar -xf "$archive" -C "$sources/extract-$name"
  rm -f "$archive"
done < "$lock"
src_dir() {
  case "$1" in
    libtasn1) echo "$sources/extract-libtasn1/libtasn1-4.21.0";;
    libpsl) echo "$sources/extract-libpsl/libpsl-0.21.5";;
    glib-networking) echo "$sources/extract-glib-networking/glib-networking-2.80.1";;
    libsoup3) echo "$sources/extract-libsoup3/libsoup-3.6.5";;
  esac
}
for name in libtasn1 libpsl glib-networking libsoup3; do
  [ -d "$(src_dir "$name")" ] || {
    echo "ERROR: unexpected source tarball layout for $name" >&2; exit 5;
  }
done
echo 'STEP=BUILD_LIBTASN1'
(
  cd "$(src_dir libtasn1)"
  ./configure --prefix="$prefix" --libdir="$prefix/lib" --disable-static \
              --enable-shared --disable-doc >"$reports/libtasn1-configure.log" 2>&1
  make -j2 >"$reports/libtasn1-build.log" 2>&1
  make install >"$reports/libtasn1-install.log" 2>&1
)
echo 'BUILT=libtasn1'
echo 'STEP=BUILD_LIBPSL'
meson setup "$work/libpsl-build" "$(src_dir libpsl)" --prefix="$prefix" --libdir=lib \
  -Ddefault_library=shared -Druntime=libicu -Dbuiltin=true -Ddocs=false -Dtests=false \
  > "$reports/libpsl-configure.log" 2>&1
meson compile -C "$work/libpsl-build" -j 2 > "$reports/libpsl-build.log" 2>&1
meson install -C "$work/libpsl-build" > "$reports/libpsl-install.log" 2>&1
echo 'BUILT=libpsl'
echo 'STEP=BUILD_GLIB_NETWORKING'
meson setup "$work/glib-networking-build" "$(src_dir glib-networking)" \
  --prefix="$prefix" --libdir=lib \
  -Ddefault_library=shared -Dgnutls=enabled -Dopenssl=disabled \
  -Dlibproxy=disabled -Dgnome_proxy=disabled -Denvironment_proxy=disabled \
  -Dinstalled_tests=false \
  > "$reports/glib-networking-configure.log" 2>&1
meson compile -C "$work/glib-networking-build" -j 2 \
  > "$reports/glib-networking-build.log" 2>&1
meson install -C "$work/glib-networking-build" > "$reports/glib-networking-install.log" 2>&1
echo 'BUILT=glib-networking'
echo 'STEP=BUILD_LIBSOUP3'
meson setup "$work/libsoup3-build" "$(src_dir libsoup3)" --prefix="$prefix" --libdir=lib \
  -Ddefault_library=shared -Dgssapi=disabled -Dntlm=disabled -Dbrotli=disabled \
  -Dtls_check=false -Dintrospection=disabled -Dvapi=disabled -Ddocs=disabled \
  -Dtests=false -Dautobahn=disabled -Dinstalled_tests=false -Dsysprof=disabled \
  -Dpkcs11_tests=disabled -Dfuzzing=disabled \
  > "$reports/libsoup3-configure.log" 2>&1
meson compile -C "$work/libsoup3-build" -j 2 > "$reports/libsoup3-build.log" 2>&1
meson install -C "$work/libsoup3-build" > "$reports/libsoup3-install.log" 2>&1
echo 'BUILT=libsoup3'
pkg-config --exists libsoup-3.0 libpsl gnutls
# Ensure these are actually linked to our private prefix rather than host replacements.
for pc in libpsl libsoup-3.0; do
  got=$(pkg-config --variable=prefix "$pc")
  [ "$got" = "$prefix" ] || {
    echo "ERROR: $pc resolved from wrong prefix $got" >&2; exit 6;
  }
done
module=$(find "$prefix" -type f -name '*giognutls*.so' -print -quit)
[ -n "$module" ] || { echo 'ERROR: missing compiled GIO GnuTLS TLS module' >&2; exit 6; }
echo "GIO_GNUTLS_MODULE=$module"
gio_dir=$(dirname "$module")
export GIO_EXTRA_MODULES="$gio_dir"
command -v gio-querymodules >/dev/null && gio-querymodules "$gio_dir" || true
cat > "$work/offline-tls-smoke.c" <<'C'
#include <gio/gio.h>
#include <libsoup/soup.h>
#include <stdio.h>
int main(void) {
    GTlsBackend *backend = g_tls_backend_get_default();
    if (!backend || !g_tls_backend_supports_tls(backend)) {
        fputs("OFFLINE_TLS_SMOKE=FAIL_TLS_BACKEND\n", stderr);
        return 19;
    }
    SoupSession *session = soup_session_new();
    if (!session) return 20;
    g_object_unref(session);
    puts("OFFLINE_TLS_SMOKE=PASS_GIO_GNUTLS_AND_LIBSOUP_SESSION");
    return 0;
}
C
cc "$work/offline-tls-smoke.c" -o "$work/offline-tls-smoke" \
  $(pkg-config --cflags --libs libsoup-3.0) \
  -Wl,-rpath,"$prefix/lib"
"$work/offline-tls-smoke"
report="$reports/ARM64-REAL-DEPENDENCIES.txt"
{
  echo 'REPORT=FIRE4NIX_ARM64_DEPENDENCIES_UBUNTU_NATIVE_ONLY'
  echo "build_libc=$(getconf GNU_LIBC_VERSION)"
  echo 'rocknix_toolchain_used=no'
  echo 'browser_compiled=no'
  echo 'target_hardware_tested=no'
  for lib in libtasn1 libpsl glib-networking libsoup3; do
    echo "BUILT_LIBRARY=$lib"
  done
  echo 'OFFLINE_TLS_SMOKE=PASS_GIO_GNUTLS_AND_LIBSOUP_SESSION'
  echo 'NOTE=DO_NOT_DEPLOY_UBUNTU_LIBRARIES_TO_ROCKNIX_DEVICE'
  echo 'ELF_AUDIT_BEGIN'
} > "$report"
while IFS= read -r -d '' lib; do
  machine=$(readelf -h "$lib" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p' | head -1)
  case "$machine" in AArch64|AARCH64) ;; *)
    echo "ERROR: non-AArch64 shared library at $lib ($machine)" >&2; exit 6 ;;
  esac
  glibc=$(readelf --version-info "$lib" 2>/dev/null |
    sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' | sort -V | tail -1 || true)
  if [ -n "$glibc" ] && ! awk -v req="$glibc" 'BEGIN{split(req,a,"."); exit !(a[1]<2 || a[1]==2 && a[2]<=41)}'; then
    echo "ERROR: $lib requires GLIBC $glibc > target 2.41" >&2; exit 6
  fi
  printf 'ELF=%s machine=%s glibc_max=%s\n' "$lib" "$machine" "${glibc:-none}" >> "$report"
done < <(find "$prefix" -type f -name '*.so*' -print0)
echo 'ELF_AUDIT_STATUS=ALL_REAL_FILES_AARCH64_GLIBC_AT_MOST_2_41' >> "$report"
cat "$report"
echo 'STATUS=ARM64_PREREQUISITES_COMPILED_ON_UBUNTU_NOT_YET_ON_ROCKNIX'
