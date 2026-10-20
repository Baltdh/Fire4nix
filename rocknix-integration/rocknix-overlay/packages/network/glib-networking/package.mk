# SPDX-License-Identifier: LGPL-2.1-or-later
# GIO TLS module for Soup3 HTTPS. Keep giognutls.so in the final private runtime.
PKG_NAME="glib-networking"
PKG_VERSION="2.80.1"
PKG_SHA256="b80e2874157cd55071f1b6710fa0b911d5ac5de106a9ee2a4c9c7bee61782f8e"
PKG_LICENSE="LGPL-2.1-or-later"
PKG_SITE="https://gitlab.gnome.org/GNOME/glib-networking"
PKG_URL="https://download.gnome.org/sources/glib-networking/2.80/glib-networking-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain meson:host ninja:host glib gnutls"
PKG_LONGDESC="GIO GnuTLS backend needed for HTTPS in WPE WebKit."
PKG_TOOLCHAIN="meson"
PKG_MESON_OPTS_TARGET="-Dgnutls=enabled -Dopenssl=disabled -Dlibproxy=disabled -Dgnome_proxy=disabled -Denvironment_proxy=disabled -Dinstalled_tests=false -Ddefault_library=shared"
