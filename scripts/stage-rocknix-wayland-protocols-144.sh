#!/usr/bin/env bash
# Stage ROCKNIX-effective wayland-protocols 1.44 as target-independent XML data.
# Do not install host ELF, write firmware or alter the ROCKNIX sysroot.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: ephemeral non-root GitHub runner required' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
source_tree="$root/rocknix-source"
[[ "$(git -C "$source_tree" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
recipe="$source_tree/projects/ROCKNIX/packages/wayland/wayland-protocols/package.mk"
grep -Fxq 'PKG_VERSION="1.44"' "$recipe"
out="$root/wayland-protocols-target"
[[ ! -e "$out" ]] || { echo 'ERROR: refuse to overwrite stage' >&2; exit 4; }
mkdir -p "$out/source" "$out/reports"
archive="$out/wayland-protocols-1.44.tar.xz"
sha=3df1107ecf8bfd6ee878aeca5d3b7afd81248a48031e14caf6ae01f14eebb50e
urls=(
  "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.44/downloads/wayland-protocols-1.44.tar.xz"
  "https://mirrors.edge.kernel.org/debian/pool/main/w/wayland-protocols/wayland-protocols_1.44.orig.tar.xz"
)
success=0
for url in "${urls[@]}"; do
  if curl --fail --location --silent --show-error --retry 2 \
    --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 120 \
    "$url" --output "$archive" && echo "$sha  $archive" | sha256sum --check; then
    success=1
    break
  fi
  rm -f "$archive"
done
[[ "$success" == 1 ]] || { echo 'ERROR: Wayland Protocols source SHA mismatch or unavailable' >&2; exit 5; }
tar -tJf "$archive" | awk '/^\// || /(^|\/)\.\.\// { bad=1 } END { exit !bad }' && {
  echo 'ERROR: unsafe archive path' >&2; exit 5;
} || true
tar -xJf "$archive" -C "$out/source" --strip-components=1
[[ -s "$out/source/meson.build" ]] || exit 5
meson setup "$out/build" "$out/source" --prefix=/usr -Dtests=false
meson compile -C "$out/build"
DESTDIR="$out/stage" meson install -C "$out/build"
test -s "$out/stage/usr/share/pkgconfig/wayland-protocols.pc"
test -d "$out/stage/usr/share/wayland-protocols"
test "$(find "$out/stage/usr/share/wayland-protocols" -name '*.xml' -type f | wc -l)" -gt 20
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$out/stage/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$out/stage"
test "$(pkg-config --modversion wayland-protocols)" = 1.44
# Architecture-independent target protocol XML; no host-linked ELF files.
if find "$out/stage" -type f -exec file {} + | grep -E 'ELF .* (executable|shared object)'; then
  echo 'ERROR: an executable from the host contaminated protocols stage' >&2; exit 6
fi
mkdir -p "$out/stage/usr/lib" "$out/stage/usr/include"
{
 echo 'WAYLAND_PROTOCOLS_VERSION=1.44_ROCKNIX_EFFECTIVE'
 echo 'WAYLAND_PROTOCOLS_SOURCE=SHA256_MATCH'
 echo 'WAYLAND_PROTOCOLS_TARGET_DATA=PASS_ARCH_INDEPENDENT'
 echo 'HOST_ELF_COPIED=NO'
 echo 'WPE_WEBKIT_BUILT=NO'
} > "$out/reports/acceptance.txt"
cat "$out/reports/acceptance.txt"
