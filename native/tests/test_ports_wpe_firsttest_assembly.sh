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
    assert 'Fire4Nix-Grafico-Resgate.sh' in names
    assert z.getinfo('Fire4Nix-Grafico-Resgate.sh').external_attr >> 16 & 0o111
    assert b'--live-auto' in z.read('Fire4Nix-Grafico-Resgate.sh')
    for entry in ('Habilitar-Teste-Ports.sh', 'Fire4Nix-Teste.sh',
                  'Diagnosticar-Fire4Nix.sh'):
        assert entry in names, 'Missing standalone diagnostic: ' + entry
        assert z.getinfo(entry).external_attr >> 16 & 0o111, entry + ' not executable'
    assert 'Fire4Nix/Fire4Nix-Iniciar.sh' in names
    assert 'Fire4Nix/www/primeiro-teste.html' in names
    offline=z.read('Fire4Nix/www/primeiro-teste.html')
    assert b'JS OK' in offline and b'PENDENTE' in offline
    assert b'3 cores' in offline
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
    # WebKit subprocesses must remain executable after GitHub artifact
    # extraction and the final Ports ZIP build, not just the main launcher.
    for name in ('WPEWebProcess', 'WPENetworkProcess'):
        info=z.getinfo('Fire4Nix/runtime/libexec/wpe-webkit-2.0/'+name)
        assert (info.external_attr >> 16 & 0o170000) == 0o100000
        assert (info.external_attr >> 16 & 0o111) == 0o111, name
    assert (z.getinfo('Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1').external_attr >> 16 & 0o111) == 0

print('PORTS_EXPERIMENTAL_ZIP_STRUCTURE=PASS_REAL_ELF_ARM64_FIXTURES')
PY
# Extract the candidate into a path with spaces and install its diagnostic
# shortcuts using the EXACT root scripts contained in the candidate ZIP.
# Never run the synthetic WebKit ELF or touch a real ROMs directory.
mkdir -p "$out/extracted candidate" "$out/roms with spaces/ports"
python3 - "$out/valid.zip" "$out/extracted candidate" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
printf 'preserve-existing-browser\n' > "$out/roms with spaces/ports/Fire4Nix.sh"
(
 cd /
 FIRE4NIX_ROMS="$out/roms with spaces" \
   sh "$out/extracted candidate/Habilitar-Teste-Ports.sh" > "$out/testkit-installed.txt"
)
grep -Fxq 'NO_WEBKIT_COPIED=1' "$out/testkit-installed.txt"
grep -Fxq 'preserve-existing-browser' "$out/roms with spaces/ports/Fire4Nix.sh"
for name in Fire4Nix-Teste-101 Fire4Nix-Grafico-101 Fire4Nix-Tela-101; do
  test -f "$out/roms with spaces/ports/$name.sh"
  grep -Fq '.Fire4Nix-Teste-101/Fire4Nix-Teste.sh' "$out/roms with spaces/ports/$name.sh"
done
grep -Fq -- '--visual-live' "$out/roms with spaces/ports/Fire4Nix-Tela-101.sh"
test -s "$out/roms with spaces/ports/.Fire4Nix-Teste-101/Fire4Nix/www/primeiro-teste.html"
test ! -e "$out/roms with spaces/ports/.Fire4Nix-Teste-101/Fire4Nix/runtime"
FIRE4NIX_ROMS="$out/roms with spaces" \
  sh "$out/extracted candidate/Habilitar-Teste-Ports.sh" > "$out/testkit-repeat.txt"
grep -Fq 'already present' "$out/testkit-repeat.txt"
echo 'PORTS_EXPERIMENTAL_TESTKIT=PASS_FROM_ZIP_ANY_CWD_NO_WEBKIT_COPIED'

# CMake emits in-runtime SONAME aliases, which should become regular ZIP
# members; ZIP symlinks and escaping aliases would be dangerous on FAT/SD.
ln -s libWPEWebKit-2.0.so.1 "$runtime/lib/libWPEWebKit-2.0.so"
ln -s libWPEWebKit-2.0.so.1 "$runtime/lib/libWPEWebKit-2.0.so.1.11.4"
python3 "$packer" --runtime "$runtime" --native "$native" \
  --installer "$root/installer" --output "$out/aliases.zip" >/dev/null
python3 - "$out/aliases.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    alias='Fire4Nix/runtime/lib/libWPEWebKit-2.0.so'
    actual='Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1'
    assert actual in z.namelist()
    assert alias not in z.namelist(), 'Unneeded linker SONAME alias duplicates huge ELF on FAT'
    assert 'Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1.11.4' not in z.namelist()
    source_manifest=z.read('Fire4Nix/runtime/SHA256SUMS.txt').decode()
    assert 'lib/libWPEWebKit-2.0.so.1' in source_manifest
    assert 'lib/libWPEWebKit-2.0.so.1.11.4' not in source_manifest
    assert 'lib/libWPEWebKit-2.0.so\n' not in source_manifest
    package_manifest=z.read('PACOTE-SHA256SUMS.txt').decode()
    assert 'Fire4Nix/runtime/SHA256SUMS.txt' in package_manifest
    assert not any(row.endswith("  "+alias) for row in package_manifest.splitlines())
print('PORTS_SAFE_WPE_SONAME_ALIAS=PASS_DEDUP_AND_CHECKSUMS')
PY
rm "$runtime/lib/libWPEWebKit-2.0.so" "$runtime/lib/libWPEWebKit-2.0.so.1.11.4"
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
