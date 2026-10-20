#!/bin/sh
# Fire4Nix 1.15.1: mock negative regressions; never executes WebKit or writes SD.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
FILE="$ROOT/installer/Fire4Nix-R36H-Teste-Seguro.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/runtime/lib" "$T/reports"
printf 'not-an-ELF\n' > "$T/runtime/lib/libWPEWebKit-2.0.so.1"

FIRE4NIX_SAFE_RUNTIME="$T/runtime" FIRE4NIX_SAFE_TMPDIR="$T/reports" \
  sh "$FILE" --safe > "$T/output"
grep -q '^test_mode=STATIC_READ_ONLY$' "$T/output"
grep -q '^webkit_elf=BAD_HEADER_OR_NOT_AARCH64$' "$T/output"
grep -q '^test_result=BLOCKED_KNOWN_RUNTIME_ABI$' "$T/output"
grep -q '^web_browser_executed=no$' "$T/output"
grep -q '^system_modified=no$' "$T/output"
grep -q '^RELATORIO=' "$T/output"
[ "$(find "$T/reports" -type f | wc -l)" -eq 1 ]

# ROCKNIX BusyBox rejects the GNU-only '.txt' suffix on mktemp templates.
# Simulate it with a strict mktemp wrapper without requiring BusyBox in CI.
mkdir -p "$T/mockbin"
cat > "$T/mockbin/mktemp" <<'MKTEMP'
#!/bin/sh
case "$1" in
  *XXXXXX) exec /usr/bin/mktemp "$@" ;;
  *) echo 'mktemp: Invalid argument' >&2; exit 1 ;;
esac
MKTEMP
chmod +x "$T/mockbin/mktemp"
FIRE4NIX_SAFE_RUNTIME="$T/runtime" FIRE4NIX_SAFE_TMPDIR="$T/reports" \
  PATH="$T/mockbin:$PATH" sh "$FILE" --safe > "$T/busybox-output"
grep -q '^test_result=BLOCKED_KNOWN_RUNTIME_ABI$' "$T/busybox-output"
[ "$(find "$T/reports" -type f | wc -l)" -eq 2 ]

# Unsafe modes and unavailable TMPDIR must fail closed (no SD fallback).
if FIRE4NIX_SAFE_TMPDIR="$T/no-dir" sh "$FILE" --safe > "$T/fail" 2>&1; then
  echo 'FAIL: fallback to SD when temp is unavailable'; exit 1
fi
if sh "$FILE" --visual > "$T/fail" 2>&1; then
  echo 'FAIL: accepted unsafe graphical option'; exit 1
fi

# The existing photo-summary mode must not invoke the dynamic WPE preflight.
mkdir -p "$T/kit/Fire4Nix/bin" "$T/kit-reports"
cp "$ROOT/installer/Fire4Nix-Teste.sh" "$T/kit/Fire4Nix-Teste.sh"
cat > "$T/kit/Fire4Nix/bin/fire4nix-native-aarch64" <<'BIN'
#!/bin/sh
if [ "$1" = --selftest ]; then echo 'mock selftest'; exit 0; fi
echo 'UNEXPECTED_WEBKIT_CALL' >&2
exit 99
BIN
cat > "$T/kit/Diagnosticar-Fire4Nix.sh" <<'DIAG'
#!/bin/sh
printf '%s\n' "$1" > "$FIRE4NIX_DIAGNOSTIC_OUT.mode"
printf 'WPE_library=missing\nWPEPlatform_preflight=skipped_safe_mode_no_library_execution\n' > "$FIRE4NIX_DIAGNOSTIC_OUT"
DIAG
chmod +x "$T/kit/Fire4Nix/bin/fire4nix-native-aarch64"
FIRE4NIX_TEST_REPORT_DIR="$T/kit-reports" sh "$T/kit/Fire4Nix-Teste.sh" --screen > "$T/screen"
grep -q '^--safe$' "$T/kit-reports/Fire4Nix-Diagnostico-101.txt.mode"
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/screen"
! grep -q 'UNEXPECTED_WEBKIT_CALL' "$T/screen"
echo 'PASS: safe R36H, BusyBox mktemp, bad ELF and no WPE dynamic execution'
