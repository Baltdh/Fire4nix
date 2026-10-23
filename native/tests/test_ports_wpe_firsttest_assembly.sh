#!/usr/bin/env bash
# Run with real ELF ARM64 fixtures. Does not build or execute WebKit itself.
set -euo pipefail
test "$(uname -m)" = aarch64
root=$(cd "$(dirname "$0")/../.." && pwd -P)
native="$FIRE4NIX_NATIVE_086_ELF"
test -s "$native"
test "$(sha256sum "$native" | awk '{print $1}')" = \
  4295f354873519802fc5817a1ee6d194489d1cc824fcd8e2cb65569d0fa0f1f4
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
runtime="$out/runtime"
mkdir -p "$runtime/lib" "$runtime/libexec/wpe-webkit-2.0" \
  "$runtime/lib/wpe-webkit-2.0/injected-bundle" "$runtime/share/wpe-webkit-2.0"
cat > "$out/webkit.c" <<'EOF'
int webkit_web_view_get_wpe_view(void) { return 1; }
EOF
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 "$out/webkit.c" \
  -o "$runtime/lib/libWPEWebKit-2.0.so.1"
cat > "$out/process.c" <<'EOF'
int main(void) { return 0; }
EOF
for helper in WPEWebProcess WPENetworkProcess; do
 cc -fPIE -pie "$out/process.c" -o "$runtime/libexec/wpe-webkit-2.0/$helper"
done
cat > "$out/injected.c" <<'EOF'
int injected_bundle_entry(void) { return 3; }
EOF
cc -shared -fPIC -Wl,-soname,libWPEInjectedBundle.so "$out/injected.c" \
  -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
echo 'Synthetic resource fixture - not from WebKit' > "$runtime/share/wpe-webkit-2.0/inspector.gresource"
cat > "$runtime/BUILD-REPORT.txt" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
cat > "$runtime/SDK-BUNDLE-REPORT.txt" <<'EOF'
ROCKNIX_PRIVATE_SDK_ELF_BUNDLE=PASS_STATIC_SONAMES_ONLY
WPE_RUNTIME_CLOSURE=SDK_STATIC_CANDIDATES_ONLY
WPE_INJECTED_BUNDLE_ELF_AUDITED=yes
R36H_INSTALLABLE=no
EOF
(
 cd "$runtime"
 find lib libexec share -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)
packer="$root/scripts/package-first-r36h-ports-candidate.py"
python3 "$packer" --runtime "$runtime" --native "$native" \
 --installer "$root/installer" --output "$out/valid.zip" > "$out/success.txt"
grep -Fxq 'FIRST_TEST_PORTS_CANDIDATE=PASS_STATIC_ARM64_NOT_HARDWARE_TESTED' "$out/success.txt"
python3 - "$out/valid.zip" <<'PY'
from pathlib import Path
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    names=set(z.namelist())
    assert 'Fire4Nix-Direto.sh' in names
    assert 'Fire4Nix/Fire4Nix-Iniciar.sh' in names
    assert 'Fire4Nix/bin/fire4nix-native-aarch64' in names
    assert 'Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1' in names
    assert 'Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPEWebProcess' in names
    assert 'Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess' in names
    assert 'Fire4Nix/runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so' in names
    assert 'Fire4Nix/runtime/share/wpe-webkit-2.0/inspector.gresource' in names
    assert b'R36H_FIRST_FRAME_VERIFIED=no' in z.read('LEIA-ME-PRIMEIRO.txt')
    assert len(names)==len(z.namelist())
    assert z.getinfo('Fire4Nix-Direto.sh').external_attr >> 16 & 0o111
    assert z.getinfo('Fire4Nix/bin/fire4nix-native-aarch64').external_attr >> 16 & 0o111
print('PORTS_EXPERIMENTAL_ZIP_STRUCTURE=PASS_REAL_ELF_ARM64_FIXTURES')
PY
# CMake emits in-runtime SONAME aliases, which should become regular ZIP
# members; ZIP symlinks and escaping aliases would be dangerous on FAT/SD.
ln -s libWPEWebKit-2.0.so.1 "$runtime/lib/libWPEWebKit-2.0.so"
python3 "$packer" --runtime "$runtime" --native "$native" \
  --installer "$root/installer" --output "$out/aliases.zip" >/dev/null
python3 - "$out/aliases.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    alias='Fire4Nix/runtime/lib/libWPEWebKit-2.0.so'
    actual='Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1'
    assert alias in z.namelist()
    assert z.read(alias)==z.read(actual)
    assert (z.getinfo(alias).external_attr >> 16 & 0o170000) == 0o100000
print('PORTS_SAFE_WPE_SONAME_ALIAS=PASS_REGULAR_FILE_CONTENT')
PY
rm "$runtime/lib/libWPEWebKit-2.0.so"
ln -s /etc/passwd "$runtime/lib/libWPEWebKit-2.0.so"
if python3 "$packer" --runtime "$runtime" --native "$native" \
  --installer "$root/installer" --output "$out/escape-fail.zip" > /dev/null 2>&1; then
 echo 'ERROR: absolute path symlink was packed' >&2; exit 1
fi
test ! -e "$out/escape-fail.zip"
rm "$runtime/lib/libWPEWebKit-2.0.so"
# A corrupted asset hash must prevent generating another archive.
echo 'changed' >> "$runtime/share/wpe-webkit-2.0/inspector.gresource"
if python3 "$packer" --runtime "$runtime" --native "$native" \
 --installer "$root/installer" --output "$out/hash-fail.zip" > "$out/error.log" 2>&1; then
 echo 'ERROR: bad runtime checksum accepted' >&2; exit 1
fi
test ! -e "$out/hash-fail.zip"
# A forged success report with no injected bundle must fail closed.
rm "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
if python3 "$packer" --runtime "$runtime" --native "$native" \
 --installer "$root/installer" --output "$out/injected-fail.zip" >/dev/null 2>&1; then
 echo 'ERROR: missing injected bundle accepted' >&2; exit 1
fi
test ! -e "$out/injected-fail.zip"
echo 'PORTS_FIRST_TEST_PACKAGER=PASS_NATIVE_AARCH64_FIXTURE_NO_DEVICE_EXECUTION'
