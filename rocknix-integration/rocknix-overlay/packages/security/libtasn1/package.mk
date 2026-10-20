# SPDX-License-Identifier: GPL-3.0-or-later
# Fire4Nix WPE WebKit 2.54.1 private ROCKNIX 20260801 build overlay.
# NOT part of the device firmware: build-host source recipe only.
PKG_NAME="libtasn1"
PKG_VERSION="4.21.0"
PKG_SHA256="1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87"
PKG_LICENSE="LGPL-2.1-or-later"
PKG_SITE="https://www.gnu.org/software/libtasn1/"
PKG_URL="https://ftp.gnu.org/gnu/libtasn1/libtasn1-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="ASN.1 library required by WPE WebKit 2.54.1."
PKG_TOOLCHAIN="configure"
PKG_CONFIGURE_OPTS_TARGET="--disable-doc --disable-valgrind-tests"
