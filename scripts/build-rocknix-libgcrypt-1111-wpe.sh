#!/usr/bin/env bash
# Build libgpg-error 1.55 and libgcrypt 1.11.1 for ROCKNIX RK3326 AArch64.
# Never install into host/target /usr or execute target ELF on the host.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: genuine, non-root GitHub Actions build environment required' >&2; exit 4;
}
base="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$base" ]] || { echo 'ERROR: run from workspace root' >&2; exit 4; }
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
ar="$sdk/bin/aarch64-rocknix-linux-gnu-ar"
ranlib="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib"
strip="$sdk/bin/aarch64-rocknix-linux-gnu-strip"
work="$base/libgcrypt-target"
stage="$work/stage"
reports="$work/reports"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing existing workdir' >&2; exit 4; }
test "$(git -C "$base/rocknix-source" rev-parse HEAD)" = 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
test -s "$sdk/fire4nix-toolchain.cmake"
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
mkdir -p "$reports" "$stage"

gpg_recipe="$base/rocknix-source/packages/security/libgpg-error/package.mk"
gcrypt_recipe="$base/rocknix-source/packages/security/libgcrypt/package.mk"
gpg_hash=95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78
gcrypt_hash=24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e
grep -Fxq 'PKG_VERSION="1.55"' "$gpg_recipe"
grep -Fxq "PKG_SHA256=\"$gpg_hash\"" "$gpg_recipe"
grep -Fxq 'PKG_VERSION="1.11.1"' "$gcrypt_recipe"
grep -Fxq "PKG_SHA256=\"$gcrypt_hash\"" "$gcrypt_recipe"
gpg_override="$base/rocknix-source/projects/ROCKNIX/packages/security/libgpg-error/package.mk"
grep -Fq -- '--disable-static --enable-shared' "$gpg_override"
grep -Fq 'libgpg-error' "$gcrypt_recipe"

get_source() {
  local name=$1 ver=$2 hash=$3 archive="$work/$1-$2.tar.bz2" url
  local ok=0
  for url in \
    "https://www.gnupg.org/ftp/gcrypt/$name/$name-$ver.tar.bz2" \
    "https://gnupg.org/ftp/gcrypt/$name/$name-$ver.tar.bz2"; do
    rm -f "$archive"
    if curl -fLsS --proto '=https' --proto-redir '=https' \
       --retry 2 --connect-timeout 14 --max-time 150 "$url" -o "$archive" &&
       echo "$hash  $archive" | sha256sum -c -; then
      printf '%s_URL=%s\n%s_SHA256=%s\n' "$name" "$url" "$name" "$hash" |
        tee -a "$reports/sources.txt"
      ok=1; break
    fi
  done
  [[ "$ok" == 1 ]] || { echo "ERROR: $name $ver release hash mismatch/unavailable" >&2; return 6; }
  tar -tjf "$archive" > "$reports/$name-archive-members.txt"
  grep -Fxq "$name-$ver/configure" "$reports/$name-archive-members.txt" || {
    echo "ERROR: $name release archive lacks configure" >&2; return 6;
  }
  mkdir -p "$work/$name-source"
  tar -xjf "$archive" -C "$work/$name-source" --strip-components=1
  test -s "$work/$name-source/configure"
}
get_source libgpg-error 1.55 "$gpg_hash"
get_source libgcrypt 1.11.1 "$gcrypt_hash"
printf 'GCRYPT_SOURCES=PASS_ROCKNIX_ORIGINAL_SHA256\n' | tee -a "$reports/sources.txt"

# Effective ROCKNIX override requires shared libgpg-error, unlike the base
# package's static-only defaults. Match the PROJECT override exactly.
mkdir -p "$work/gpg-build" "$work/gcrypt-build"
export CFLAGS='-O2 -mcpu=cortex-a35 -fPIC'
export CPPFLAGS=''
export LDFLAGS=''
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
export CC="$cc" AR="$ar" RANLIB="$ranlib" STRIP="$strip"
export CC_FOR_BUILD=gcc
(
  cd "$work/gpg-build"
  "$work/libgpg-error-source/configure" \
    --host=aarch64-rocknix-linux-gnu --build="$(gcc -dumpmachine)" \
    --prefix=/usr --libdir=/usr/lib \
    --disable-static --enable-shared --disable-nls --disable-rpath \
    --with-gnu-ld --with-pic \
    > "$reports/gpg-configure.log" 2>&1
) || {
  echo 'GPGERROR_TARGET_CONFIGURE=BLOCKED'
  tail -n 115 "$reports/gpg-configure.log"; exit 7;
}
make -C "$work/gpg-build" -j2 > "$reports/gpg-build.log" 2>&1 || {
  echo 'GPGERROR_TARGET_BUILD=BLOCKED'
  tail -n 125 "$reports/gpg-build.log"; exit 8;
}
make -C "$work/gpg-build" DESTDIR="$stage" install \
  > "$reports/gpg-install.log" 2>&1 || {
  echo 'GPGERROR_TARGET_INSTALL=BLOCKED'
  tail -n 110 "$reports/gpg-install.log"; exit 9;
}
test -s "$stage/usr/lib/libgpg-error.so.0"
test -s "$stage/usr/include/gpg-error.h"
readelf -h "$stage/usr/lib/libgpg-error.so.0" | grep -Eq 'Machine:.*AArch64'
readelf -d "$stage/usr/lib/libgpg-error.so.0" > "$reports/libgpg-error-dynamic.txt"
grep -Fq 'Shared library: [libc.so.6]' "$reports/libgpg-error-dynamic.txt"
# Confirm gpg-error-config and .pc refer to the stage, not host libraries.
if [[ -s "$stage/usr/bin/gpg-error-config" ]]; then
  sed -i -e "s:\(['= ]\)/usr:\1$stage/usr:g" "$stage/usr/bin/gpg-error-config"
  export PATH="$stage/usr/bin:$PATH"
fi
# ROCKNIX package's sysroot override prepares lock-obj headers for its ABI.
# Never copy an Ubuntu lock-obj-pub.h into the cross build.
if [[ -s "$work/libgpg-error-source/src/syscfg/lock-obj-pub.aarch64-unknown-linux-gnu.h" ]]; then
  printf 'GPGERROR_AARCH64_LOCK_HEADER=FOUND\n' | tee "$reports/lock-header.txt"
fi
echo 'GPGERROR_BUILD=PASS_ROCKNIX_AARCH64_SHARED_EFFECTIVE_PROFILE' | tee "$reports/gpg-result.txt"

export CPPFLAGS="-I$stage/usr/include"
export LDFLAGS="-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib"
export LIBGPG_ERROR_CFLAGS="-I$stage/usr/include"
export LIBGPG_ERROR_LIBS="-L$stage/usr/lib -lgpg-error"
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig"
export PKG_CONFIG_PATH=''
export PKG_CONFIG_SYSROOT_DIR="$stage"
(
  cd "$work/gcrypt-build"
  "$work/libgcrypt-source/configure" \
    --host=aarch64-rocknix-linux-gnu --build="$(gcc -dumpmachine)" \
    --prefix=/usr --libdir=/usr/lib \
    --enable-shared --enable-static --enable-asm \
    --with-gnu-ld --with-libgpg-error-prefix="$stage/usr" \
    --disable-doc \
    ac_cv_sys_symbol_underscore=no \
    > "$reports/gcrypt-configure.log" 2>&1
) || {
  echo 'LIBGCRYPT_TARGET_CONFIGURE=BLOCKED'
  tail -n 145 "$reports/gcrypt-configure.log"; exit 10;
}
make -C "$work/gcrypt-build" -j2 > "$reports/gcrypt-build.log" 2>&1 || {
  echo 'LIBGCRYPT_TARGET_BUILD=BLOCKED'
  tail -n 150 "$reports/gcrypt-build.log"; exit 11;
}
make -C "$work/gcrypt-build" DESTDIR="$stage" install \
  > "$reports/gcrypt-install.log" 2>&1 || {
  echo 'LIBGCRYPT_TARGET_INSTALL=BLOCKED'
  tail -n 120 "$reports/gcrypt-install.log"; exit 12;
}
so="$stage/usr/lib/libgcrypt.so.20"
test -s "$so" || { echo 'ERROR: real libgcrypt.so.20 missing' >&2; exit 13; }
test -s "$stage/usr/include/gcrypt.h"
readelf -h "$so" > "$reports/libgcrypt-elf-header.txt"
readelf -d "$so" > "$reports/libgcrypt-elf-dynamic.txt"
readelf -V "$so" > "$reports/libgcrypt-elf-versions.txt"
readelf -Ws "$so" > "$reports/libgcrypt-elf-symbols.txt"
grep -Eq 'Class:.*ELF64' "$reports/libgcrypt-elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$reports/libgcrypt-elf-header.txt"
grep -Fq '(SONAME)' "$reports/libgcrypt-elf-dynamic.txt"
grep -Fq 'Shared library: [libgpg-error.so.0]' "$reports/libgcrypt-elf-dynamic.txt"
grep -Eq 'GLOBAL.*DEFAULT.*gcry_check_version' "$reports/libgcrypt-elf-symbols.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$reports/libgcrypt-elf-dynamic.txt"; then
  echo 'ERROR: unexpected GStreamer or TEXTREL' >&2; exit 13;
fi
python3 - "$reports/libgcrypt-elf-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x<=(2,41) for x in v),v
print('LIBGCRYPT_GLIBC=PASS_MAX_2_41')
PY
cat > "$reports/consumer.c" <<'C'
#include <gcrypt.h>
int fire4nix_wpe_crypto_probe(void) {
  unsigned char digest[64]={0};
  const char *v=gcry_check_version(GCRYPT_VERSION);
  gcry_md_hash_buffer(GCRY_MD_SHA256,digest,"offline-r36h",12);
  return v && digest[0] >= 0;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include" "$reports/consumer.c" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -Wl,--no-as-needed \
  -lgcrypt -lgpg-error -o "$reports/libfire4nix-wpe-libgcrypt-consumer.so"
readelf -h "$reports/libfire4nix-wpe-libgcrypt-consumer.so" > "$reports/consumer-header.txt"
readelf -d "$reports/libfire4nix-wpe-libgcrypt-consumer.so" > "$reports/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$reports/consumer-header.txt"
grep -Fq 'Shared library: [libgcrypt.so.20]' "$reports/consumer-dynamic.txt"
grep -Fq 'Shared library: [libgpg-error.so.0]' "$reports/consumer-dynamic.txt"
{
  echo 'LIBGCRYPT_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64'
  echo 'LIBGCRYPT_VERSION=1.11.1'
  echo 'LIBGPG_ERROR_VERSION=1.55'
  echo 'LIBGPG_ERROR_SHARED_EFFECTIVE_ROCKNIX=YES'
  echo 'LIBGCRYPT_ORIGINAL_HASHES=VERIFIED_ROCKNIX'
  echo 'LIBGCRYPT_CONSUMER_LINK=PASS_ELF64_AARCH64'
  echo 'GLIBC_MAX_ALLOWED=2.41'
  echo 'WPE_WEBKIT_BUILT=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$reports/acceptance.txt"
cat "$reports/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
