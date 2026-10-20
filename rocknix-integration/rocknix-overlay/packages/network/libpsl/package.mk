# SPDX-License-Identifier: MIT
# Fire4Nix build overlay. libpsl uses ROCKNIX ICU, no libidn2/unistring overlay.
PKG_NAME="libpsl"
PKG_VERSION="0.21.5"
PKG_SHA256="1dcc9ceae8b128f3c0b3f654decd0e1e891afc6ff81098f227ef260449dae208"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/rockdaboot/libpsl"
PKG_URL="https://github.com/rockdaboot/libpsl/releases/download/${PKG_VERSION}/libpsl-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain meson:host ninja:host icu Python3:host"
PKG_LONGDESC="Public Suffix List validation for Soup3, with ICU IDNA support."
PKG_TOOLCHAIN="meson"
PKG_MESON_OPTS_TARGET="-Druntime=libicu -Dbuiltin=true -Ddocs=false -Dtests=false -Ddefault_library=shared"
