#!/bin/sh
# Offline smoke tests for dual-SD WPE discovery and photo-friendly output.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/package/Fire4Nix/bin" "$T/runtime/libexec/wpe-webkit-2.0" "$T/runtime/lib"
cp "$ROOT/installer/Diagnosticar-Fire4Nix.sh" "$T/package/Diagnosticar-Fire4Nix.sh"
cat > "$T/package/Fire4Nix/bin/fire4nix-native-aarch64" <<'BROWSER'
#!/bin/sh
printf '[FIRE4NIX-ABI] webkit_library=mocked\n'
printf '[FIRE4NIX-ABI] wpe_toplevel_fullscreen=absent\n'
exit 78
BROWSER
chmod +x "$T/package/Fire4Nix/bin/fire4nix-native-aarch64"
printf 'MOCK-lib' > "$T/runtime/lib/libWPEWebKit-2.0.so.1"
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'MOCK-process' > "$T/runtime/libexec/wpe-webkit-2.0/$p"
done
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/found.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --screen > "$T/screen.txt"
grep -q '^WPE_library=present$' "$T/found.txt"
grep -q '^WPEWebProcess=present$' "$T/found.txt"
grep -q '^WPENetworkProcess=present$' "$T/found.txt"
grep -q '^WPEGPUProcess=present$' "$T/found.txt"
grep -q '^WPEPlatform_preflight_exit=78$' "$T/found.txt"
grep -q '^WPEPlatform_preflight_note=legacy_library_without_new_API$' "$T/found.txt"
grep -q '\[FIRE4NIX-ABI\] wpe_toplevel_fullscreen=absent' "$T/found.txt"
grep -q 'RESUMO PARA FOTO' "$T/screen.txt"
grep -q 'WPEPlatform_preflight_exit=78' "$T/screen.txt"
grep -q 'GRAPHICS_STATUS=NOT_VERIFIED_BY_PREFLIGHT' "$T/screen.txt"
# When run directly from an extracted package on SD2, no local runtime
# should be mistaken for a functioning graphics engine.
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/nonexistent" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/missing.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --screen > "$T/missing-screen.txt"
grep -q '^WPE_library=missing$' "$T/missing.txt"
grep -q '^WPE_runtime_source=not_found_on_checked_SD_paths$' "$T/missing.txt"
grep -q '^WPEPlatform_preflight=skipped_missing_binary' "$T/missing.txt" && exit 51
# Binary is available, but launcher in this test is deliberately absent.
grep -q '^WPEPlatform_preflight=skipped_missing_binary' "$T/missing.txt" && exit 52
echo "PASS: dual-SD override, external WPE library, legacy status 78, screen-friendly report and missing-runtime distinction"
