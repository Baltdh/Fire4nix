#!/bin/sh
# Test runtime selection across SD roots without real WPE/WebKit.
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
[ -n "${FIRE4NIX_TEST_PKG:-}" ] || { echo 'Set FIRE4NIX_TEST_PKG to CI distribution directory' >&2; exit 2; }
mkdir -p "$T/pkg" "$T/roms/tools/Fire4Nix/runtime/lib" \
 "$T/roms/tools/Fire4Nix/runtime/libexec/wpe-webkit-2.0" \
 "$T/roms/ports/Fire4Nix/runtime/lib" \
 "$T/roms/ports/Fire4Nix/runtime/libexec/wpe-webkit-2.0"
cp -a "${FIRE4NIX_TEST_PKG}/." "$T/pkg/"
cat > "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64" <<'FAKE'
#!/bin/sh
[ "${1:-}" = --check-platform ] || exit 127
case "${LD_LIBRARY_PATH:-}" in
 */tools/Fire4Nix/runtime/lib*) exit 78 ;;
esac
exit 0
FAKE
chmod +x "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64"
for name in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
 echo dummy > "$T/roms/tools/Fire4Nix/runtime/libexec/wpe-webkit-2.0/$name"
 echo dummy > "$T/roms/ports/Fire4Nix/runtime/libexec/wpe-webkit-2.0/$name"
done
printf 'old-incompatible-lib' > "$T/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1"
# The selection must use a genuine AArch64 ELF mock, not arbitrary text.
printf 'const char *wpe_marker = "working-new-lib";\n' |
  cc -x c -shared -fPIC -o "$T/roms/ports/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1" -
FIRE4NIX_ROMS="$T/roms" sh "$T/pkg/Instalar-Fire4Nix-Uma-Vez.sh" > "$T/install.log"
grep -q 'Skipping incompatible WebKit runtime' "$T/install.log"
grep -q 'Selected compatible WebKit runtime:' "$T/install.log"
grep -q 'working-new-lib' "$T/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1"
# Installing a newer bundled engine MUST replace the previously selected engine,
# even if every single script and launcher byte remains unchanged.
mkdir -p "$T/pkg/Fire4Nix/runtime/lib" "$T/pkg/Fire4Nix/runtime/libexec/wpe-webkit-2.0"
cp -a "$T/roms/ports/Fire4Nix/runtime/." "$T/pkg/Fire4Nix/runtime/"
printf 'const char *wpe_marker = "new-bundled-WPE";\n' |
  cc -x c -shared -fPIC -o "$T/pkg/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1" -
FIRE4NIX_ROMS="$T/roms" sh "$T/pkg/Instalar-Fire4Nix-Uma-Vez.sh" > "$T/upgrade.log"
grep -q 'new-bundled-WPE' "$T/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1"
! grep -q 'already installed' "$T/upgrade.log"
# If no runtime passes preflight, refuse to overwrite a working installation.
cat > "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64" <<'FAIL'
#!/bin/sh
exit 78
FAIL
chmod +x "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64"
set +e
FIRE4NIX_ROMS="$T/roms" sh "$T/pkg/Instalar-Fire4Nix-Uma-Vez.sh" > "$T/rejected.log" 2>&1
status=$?
set -e
test "$status" -eq 5
grep -q 'none passed WPEPlatform preflight' "$T/rejected.log"
grep -q 'new-bundled-WPE' "$T/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1"
echo 'PASS: reject legacy runtime, select alternate SD, upgrade bundled WPE and preserve previous install on incompatible ABI'
