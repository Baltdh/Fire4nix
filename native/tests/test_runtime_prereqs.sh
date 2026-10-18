#!/bin/sh
# Offline safe-mode regression: no WPE binary or window is executed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/bin" "$T/pkg/Fire4Nix/bin" "$T/runtime/lib" "$T/runtime/libexec/wpe-webkit-2.0"
cp "$ROOT/installer/Diagnosticar-Fire4Nix.sh" "$T/pkg/Diagnosticar-Fire4Nix.sh"
printf "mock WPE" > "$T/runtime/lib/libWPEWebKit-2.0.so.1"
printf "mock EGL" > "$T/runtime/lib/libEGL.so.1"
printf "mock font" > "$T/fallback.ttf"
cat > "$T/bin/fc-list" <<'FONTS'
#!/bin/sh
printf "%s\\n" "$MOCK_FONT_FILE"
FONTS
cat > "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64" <<'BROWSER'
#!/bin/sh
echo "unexpected native execution" >> "$MOCK_NATIVE_EXECUTED"
exit 99
BROWSER
chmod +x "$T/bin/fc-list" "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64"
MOCK_FONT_FILE="$T/fallback.ttf" MOCK_NATIVE_EXECUTED="$T/native-was-run" \
  FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/audit.txt" \
  PATH="$T/bin:$PATH" sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --safe > "$T/photo.txt"
grep -q "^fontconfig_fonts=present$" "$T/audit.txt"
grep -q "^private_library_conflict_candidate=libEGL.so.1$" "$T/audit.txt"
grep -q "^bubblewrap=" "$T/audit.txt"
grep -q "^shared_mime_database=" "$T/audit.txt"
grep -q "^wpe_direct_glibc_compat=" "$T/audit.txt"
grep -q "^WPEPlatform_preflight=skipped_safe_mode_no_library_execution$" "$T/audit.txt"
test ! -e "$T/native-was-run"
grep -q "^fontconfig_fonts=present$" "$T/photo.txt"
cat > "$T/bin/fc-list" <<'NOFONTS'
#!/bin/sh
exit 0
NOFONTS
MOCK_NATIVE_EXECUTED="$T/native-was-run" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/no-fonts.txt" PATH="$T/bin:$PATH" \
  sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --safe >/dev/null
grep -q "^fontconfig_fonts=none_found$" "$T/no-fonts.txt"
test ! -e "$T/native-was-run"
echo "PASS: font detection, runtime warning, safe-mode does not load WPE"
