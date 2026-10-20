#!/bin/sh
# Validate proposed ROCKNIX 20260801 package overlay WITHOUT compiling it.
set -eu
self=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
overlay=${FIRE4NIX_ROCKNIX_OVERLAY:-"$self/rocknix-overlay"}
lock=${FIRE4NIX_DEPENDENCY_LOCK:-"$self/rocknix-wpe-prerequisites.lock"}
[ -r "$lock" ] && [ -d "$overlay" ] || {
  echo 'ERROR: source lock or overlay directory missing' >&2
  exit 4
}
count=0
check() {
  name=$1; path=$2; version=$3; toolchain=$4
  file="$overlay/packages/$path/$name/package.mk"
  [ -f "$file" ] && [ ! -L "$file" ] || {
    echo "ERROR: missing or symlinked ROCKNIX recipe $name" >&2; return 1
  }
  sha=$(awk -F '|' -v name="$name" '$1==name {print $2}' "$lock")
  [ "$(printf '%s\n' "$sha" | wc -l)" -eq 1 ] && [ -n "$sha" ] || {
    echo "ERROR: $name absent or duplicated in lock" >&2; return 1
  }
  for line in "PKG_NAME=\"$name\"" "PKG_VERSION=\"$version\"" \
              "PKG_SHA256=\"$sha\"" "PKG_TOOLCHAIN=\"$toolchain\""; do
    grep -Fqx "$line" "$file" || {
      echo "ERROR: missing exact metadata in $name: $line" >&2; return 1
    }
  done
  grep -Eq '^PKG_URL="https://[^"]+"$' "$file" || {
    echo "ERROR: non-HTTPS or missing download URL in $name" >&2; return 1
  }
  grep -Eq '^PKG_DEPENDS_TARGET="[^"]+"$' "$file" || {
    echo "ERROR: missing ROCKNIX target dependencies in $name" >&2; return 1
  }
  deps=$(sed -n 's/^PKG_DEPENDS_TARGET="\([^"]*\)"$/\1/p' "$file")
  shift 4
  for dep do
    case " $deps " in *" $dep "*) ;; *)
      echo "ERROR: $name must depend on $dep" >&2; return 1 ;;
    esac
  done
  echo "RECIPE_LOCKED=$name:$version"
  count=$((count+1))
}
check libtasn1 security 4.21.0 configure toolchain
check libpsl network 0.21.5 meson toolchain icu Python3:host
check glib-networking network 2.80.1 meson toolchain glib gnutls
check libsoup3 web 3.6.5 meson toolchain glib nghttp2 sqlite libpsl glib-networking
# Guard cross-compile characteristics that cannot be inferred from metadata.
grep -Fq 'PKG_SOURCE_DIR="libsoup-${PKG_VERSION}"' \
  "$overlay/packages/web/libsoup3/package.mk" || {
  echo 'ERROR: libsoup3 tarball extracts upstream libsoup-* directory' >&2; exit 5
}
grep -Fq -- '-Dtls_check=false' "$overlay/packages/web/libsoup3/package.mk" || {
  echo 'ERROR: libsoup cross-build cc.run TLS check must be disabled' >&2; exit 5
}
grep -Fq -- '-Dgnutls=enabled' \
  "$overlay/packages/network/glib-networking/package.mk" || {
  echo 'ERROR: GNUTLS GIO module cannot be disabled' >&2; exit 5
}
grep -Fq -- '-Druntime=libicu' "$overlay/packages/network/libpsl/package.mk" || {
  echo 'ERROR: libpsl must use pinned ROCKNIX ICU IDN provider' >&2; exit 5
}
[ "$count" -eq 4 ] || exit 5
echo 'ROCKNIX_OVERLAY_STATUS=FOUR_PINNED_RECIPES_METADATA_VERIFIED_NOT_COMPILED'
echo 'RUNTIME_TLS_MODULE=GIO_GNUTLS_REQUIRED_NOT_VERIFIED'
