# SPDX-License-Identifier: LGPL-2.0-or-later
# Soup3 uses cross-build-safe TLS option. Runtime MUST contain glib-networking.
PKG_NAME="libsoup3"
PKG_VERSION="3.6.5"
PKG_SHA256="6891765aac3e949017945c3eaebd8cc8216df772456dc9f460976fbdb7ada234"
PKG_LICENSE="LGPL-2.0-or-later"
PKG_SITE="https://libsoup.org/"
PKG_URL="https://download.gnome.org/sources/libsoup/3.6/libsoup-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain meson:host ninja:host glib nghttp2 sqlite libpsl glib-networking"
PKG_LONGDESC="libsoup 3 HTTP(S) engine for WPE WebKit 2.54.1."
PKG_TOOLCHAIN="meson"
# Upstream Meson tls_check uses cc.run(): incompatible with a cross compiler.
# Disabling the COMPILE-TIME check does NOT disable TLS: giognutls must be
# installed and tested on the target; never ship without glib-networking.
PKG_MESON_OPTS_TARGET="-Dgssapi=disabled -Dntlm=disabled -Dbrotli=disabled -Dtls_check=false -Dintrospection=disabled -Dvapi=disabled -Ddocs=disabled -Dtests=false -Dautobahn=disabled -Dinstalled_tests=false -Dsysprof=disabled -Dpkcs11_tests=disabled -Dfuzzing=disabled -Ddefault_library=shared"
