#!/usr/bin/env bash
# Cross-compile GLib 2.85.1 using genuine ROCKNIX AArch64 compiler + private stage.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: non-root CI only'; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
stage="$root/six-artifact/stage"
work="$root/glib-target"
[[ ! -e "$work" && ! -L "$work" ]] || exit 4
mkdir -p "$work"/{source,reports,stage}
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
recipe="$root/rocknix-source/packages/devel/glib/package.mk"
hash=d3f57bcd4202d93aa547ffa1d2a5dbd380a05dbaac04cc291bd7dfce93b4a8e5
grep -Fxq 'PKG_VERSION="2.85.1"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
test -f "$sysroot/usr/lib/libc.so.6"
for f in "$stage/usr/lib/libffi.a" "$stage/usr/lib/libpcre2-8.a" "$stage/usr/lib/libpcre2-16.a" "$stage/usr/lib/libz.so.1"; do test -s "$f"; done
curl --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 15 --max-time 150 https://download.gnome.org/sources/glib/2.85/glib-2.85.1.tar.xz -o "$work/source.tar.xz"
echo "$hash  $work/source.tar.xz" | sha256sum -c -
tar -xJf "$work/source.tar.xz" --strip-components=1 -C "$work/source"
cat > "$work/cross.ini" <<EOF
[binaries]
c = '$cc'
cpp = '$sdk/bin/aarch64-rocknix-linux-gnu-g++'
ar = '$sdk/bin/aarch64-rocknix-linux-gnu-ar'
strip = '$sdk/bin/aarch64-rocknix-linux-gnu-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'cortex-a35'
endian = 'little'
[properties]
sys_root = '$sysroot'
pkg_config_libdir = ['$stage/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35', '-I$stage/usr/include']
c_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
cpp_args = ['-mcpu=cortex-a35', '-I$stage/usr/include']
cpp_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
EOF
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$sysroot"
echo 'GLIB_CROSS_CONFIGURE=START'
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload -Ddefault_library=shared -Dlibmount=disabled -Dselinux=disabled -Dintrospection=disabled -Dtests=false -Dinstalled_tests=false -Ddocumentation=false -Dman=false -Dgtk_doc=false -Dnls=disabled -Ddtrace=false -Dsystemtap=false -Dforce_posix_threads=true > "$work/reports/configure.log" 2>&1; then
 echo 'GLIB_CROSS_CONFIGURE=BLOCKED'
 tail -n 105 "$work/reports/configure.log"
 exit 10
fi
echo 'GLIB_CROSS_CONFIGURE=PASS'
if ! meson compile -C "$work/build" -j 2 > "$work/reports/build.log" 2>&1; then
 echo 'GLIB_TARGET_BUILD=BLOCKED'
 tail -n 110 "$work/reports/build.log"
 exit 11
fi
echo 'GLIB_TARGET_BUILD=PASS'
if ! DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild > "$work/reports/install.log" 2>&1; then
 echo 'GLIB_INSTALL=BLOCKED'
 tail -n 90 "$work/reports/install.log"
 exit 12
fi
for name in libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 libgmodule-2.0.so.0; do
 file="$work/stage/usr/lib/$name"
 test -s "$file"
 readelf -h "$file" | grep -Eq 'Machine:.*AArch64'
 readelf -d "$file" > "$work/reports/$name.dynamic.txt"
 readelf -V "$file" > "$work/reports/$name.versions.txt"
 if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/$name.dynamic.txt"; then echo "ERROR: forbidden ELF dynamic attribute in $name"; exit 13; fi
done
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$work/stage"
for name in glib-2.0 gobject-2.0 gio-2.0 gmodule-2.0; do
 [[ $(pkg-config --modversion "$name") == 2.85.1 ]] || { echo "ERROR: missing target $name.pc"; exit 14; }
done
python3 - "$work/reports" <<'PY'
import pathlib,re,sys
for file in pathlib.Path(sys.argv[1]).glob('*.versions.txt'):
    vs=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',file.read_text())]
    assert all(v<=(2,41) for v in vs),(file,vs)
print('GLIB_ELF_GLIBC=PASS_MAX_2_41')
PY
{
 echo 'GLIB_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'GLIB_VERSION=2.85.1'
 echo 'LIBRARIES=glib,gobject,gio,gmodule'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
cat "$work/reports/result.txt" >> "$GITHUB_STEP_SUMMARY"
