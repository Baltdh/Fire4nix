#!/usr/bin/env bash
# Cross-build LibGpgError 1.55 + LibGcrypt 1.11.1 using ROCKNIX RK3326 SDK.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && "$(id -u)" != 0 && -n "$GITHUB_WORKSPACE" ]] || exit 4
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
work="$root/gcrypt-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: preexisting worktree' >&2;exit 4; }
mkdir -p "$work"/{gpg-src,gcrypt-src,gpg-build,gcrypt-build,reports,stage}
stage="$work/stage"; report="$work/reports"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
gpgr="$root/rocknix-source/packages/security/libgpg-error/package.mk"
gpgo="$root/rocknix-source/projects/ROCKNIX/packages/security/libgpg-error/package.mk"
gcr="$root/rocknix-source/packages/security/libgcrypt/package.mk"
gpgsha=95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78
gcryptsha=24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e
grep -Fxq 'PKG_VERSION="1.55"' "$gpgr"
grep -Fxq "PKG_SHA256=\"$gpgsha\"" "$gpgr"
grep -Fq -- '--enable-shared' "$gpgo"
grep -Fxq 'PKG_VERSION="1.11.1"' "$gcr"
grep -Fxq "PKG_SHA256=\"$gcryptsha\"" "$gcr"
for spec in "libgpg-error/1.55/$gpgsha" "libgcrypt/1.11.1/$gcryptsha"; do
  IFS=/ read -r name version sha <<< "$spec"
  src="$work/$name-$version.tar.bz2"
  curl --fail --location --silent --show-error --retry 2 \
   --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 150 \
   "https://www.gnupg.org/ftp/gcrypt/$name/$name-$version.tar.bz2" -o "$src"
  echo "$sha  $src" | sha256sum --check
  if [[ "$name" == libgpg-error ]]; then
    tar -xjf "$src" -C "$work/gpg-src" --strip-components=1
  else
    tar -xjf "$src" -C "$work/gcrypt-src" --strip-components=1
  fi
done
[[ -s "$work/gpg-src/configure" && -s "$work/gcrypt-src/configure" ]] || exit 5
# Mirror the ROCKNIX aarch64 syscfg fix in extracted source only.
gpg_lock="$work/gpg-src/src/syscfg/lock-obj-pub.aarch64-unknown-linux-gnu.h"
[[ -s "$gpg_lock" ]] || { echo 'ERROR: missing ROCKNIX aarch64 syscfg header' >&2;exit 5; }
cp "$gpg_lock" "$work/gpg-src/src/syscfg/lock-obj-pub.linux-gnu.h"
export CC="$cc" CXX="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
export AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar"
export RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib"
export STRIP="$sdk/bin/aarch64-rocknix-linux-gnu-strip"
export CC_FOR_BUILD=/usr/bin/gcc
export CFLAGS="-O2 -pipe -fPIC -mcpu=cortex-a35 -mno-outline-atomics"
export CPPFLAGS="-I$stage/usr/include"
export LDFLAGS="-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib"
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
build="$(gcc -dumpmachine)"; host=aarch64-rocknix-linux-gnu
export ac_cv_sys_symbol_underscore=no
if ! (cd "$work/gpg-build" && "$work/gpg-src/configure" --build="$build" --host="$host" \
  --prefix=/usr --libdir=/usr/lib --disable-static --enable-shared \
  --disable-nls --disable-rpath --with-gnu-ld --with-pic --disable-doc \
  > "$report/gpg-configure.log" 2>&1); then
  echo 'GPGERROR_CONFIGURE=BLOCKED'; tail -n 85 "$report/gpg-configure.log";exit 10
fi
if ! make -C "$work/gpg-build" -j 2 > "$report/gpg-build.log" 2>&1; then
  echo 'GPGERROR_BUILD=BLOCKED'
  grep -nE -B 4 -A 10 'error:|Error |FAILED|undefined reference' "$report/gpg-build.log" | head -n 125 || true
  tail -n 45 "$report/gpg-build.log";exit 11
fi
if ! make -C "$work/gpg-build" DESTDIR="$stage" install > "$report/gpg-install.log" 2>&1; then
  echo 'GPGERROR_INSTALL=BLOCKED';tail -n 70 "$report/gpg-install.log";exit 12
fi
[[ -s "$stage/usr/include/gpg-error.h" && -s "$stage/usr/lib/libgpg-error.so.0" ]] || exit 13
readelf -h "$stage/usr/lib/libgpg-error.so.0" | grep -Eq 'Machine:.*AArch64'
pkg-config --exists 'gpg-error >= 1.55' || {
  echo 'GPGERROR_PKGCONFIG=BLOCKED'; ls -la "$stage/usr/lib/pkgconfig" || true;exit 13;
}
export GPG_ERROR_CONFIG="$stage/usr/bin/gpg-error-config"
export GPGRT_CONFIG="$stage/usr/bin/gpgrt-config"
export GPGRT_CONFIG_LIBDIR="$stage/usr/lib"
if ! (cd "$work/gcrypt-build" && "$work/gcrypt-src/configure" --build="$build" --host="$host" \
   --prefix=/usr --libdir=/usr/lib --enable-shared --disable-static \
   --enable-asm --with-gnu-ld --with-libgpg-error-prefix="$stage/usr" --disable-doc \
   > "$report/gcrypt-configure.log" 2>&1); then
  echo 'GCRYPT_CONFIGURE=BLOCKED'
  grep -nE -B 4 -A 9 'error:|not found|cannot' "$report/gcrypt-configure.log" | head -n 120 || true
  tail -n 70 "$report/gcrypt-configure.log";exit 20
fi
if ! make -C "$work/gcrypt-build" -j 2 > "$report/gcrypt-build.log" 2>&1; then
  echo 'GCRYPT_BUILD=BLOCKED'
  grep -nE -B 4 -A 10 'error:|Error |FAILED|undefined reference' "$report/gcrypt-build.log" | head -n 120 || true
  tail -n 65 "$report/gcrypt-build.log";exit 21
fi
if ! make -C "$work/gcrypt-build" DESTDIR="$stage" install > "$report/gcrypt-install.log" 2>&1; then
  echo 'GCRYPT_INSTALL=BLOCKED';tail -n 70 "$report/gcrypt-install.log";exit 22
fi
for lib in libgpg-error.so.0 libgcrypt.so.20; do
  [[ -s "$stage/usr/lib/$lib" ]] || { echo "ERROR: missing target $lib" >&2;exit 23; }
  readelf -h "$stage/usr/lib/$lib" > "$report/$lib.header.txt"
  readelf -d "$stage/usr/lib/$lib" > "$report/$lib.dynamic.txt"
  readelf -V "$stage/usr/lib/$lib" > "$report/$lib.versions.txt"
  grep -Eq 'Machine:.*AArch64' "$report/$lib.header.txt"
  grep -Eq 'Class:.*ELF64' "$report/$lib.header.txt"
  if grep -Eq 'TEXTREL|Shared library: \[libgst' "$report/$lib.dynamic.txt";then exit 24;fi
done
[[ -s "$stage/usr/include/gcrypt.h" ]] || exit 24
grep -Fq 'Shared library: [libgpg-error.so.0]' "$report/libgcrypt.so.20.dynamic.txt"
python3 - "$report" <<'PY'
from pathlib import Path
import sys,re
for p in Path(sys.argv[1]).glob('*.versions.txt'):
 vs=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',p.read_text())]
 assert all(x<=(2,41) for x in vs),(p,vs)
print('CRYPTO_GLIBC=PASS_MAX_2_41')
PY
for pc in gpg-error libgcrypt; do
  pkg-config --exists "$pc" || { echo "ERROR: missing $pc.pc" >&2;exit 25; }
  echo "TARGET_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$report/versions.txt"
cat > "$work/consumer.c" <<'C'
#include <gcrypt.h>
#include <gpg-error.h>
int fire4nix_crypto_abi_probe(void) {
  gcry_md_hd_t h;
  if (gcry_md_open(&h, GCRY_MD_SHA256, 0)) return 1;
  gcry_md_write(h, "Fire4Nix", 8);
  gcry_md_close(h);
  return gpg_err_code(GPG_ERR_NO_ERROR);
}
C
"$cc" -shared -fPIC -O2 -mcpu=cortex-a35 -Wl,-z,defs \
  "$work/consumer.c" -I"$stage/usr/include" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -lgcrypt -lgpg-error \
  -o "$work/libfire4nix-crypto-consumer.so"
readelf -h "$work/libfire4nix-crypto-consumer.so" > "$report/consumer.header.txt"
readelf -d "$work/libfire4nix-crypto-consumer.so" > "$report/consumer.dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$report/consumer.header.txt"
grep -Fq 'Shared library: [libgcrypt.so.20]' "$report/consumer.dynamic.txt"
{
 echo 'LIBGPGERROR_VERSION=1.55_ROCKNIX_PROJECT_SHARED'
 echo 'LIBGCRYPT_VERSION=1.11.1_ROCKNIX'
 echo 'SOURCES=PASS_ROCKNIX_SHA256'
 echo 'LIBGPGERROR_TARGET=PASS_REAL_AARCH64_SHARED'
 echo 'LIBGCRYPT_TARGET=PASS_REAL_AARCH64_SHARED'
 echo 'LIBGCRYPT_CONSUMER_LINK=PASS_ELF64_AARCH64'
 echo 'GLIBC_MAX=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
