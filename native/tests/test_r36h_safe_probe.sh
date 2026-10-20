#!/bin/sh
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
if FIRE4NIX_SAFE_TMPDIR="$T/no-dir" sh "$FILE" --safe > "$T/fail" 2>&1; then
  echo 'FAIL: fallback to SD when temp is unavailable'; exit 1
fi
if sh "$FILE" --visual > "$T/fail" 2>&1; then
  echo 'FAIL: accepted unsafe graphical option'; exit 1
fi
echo 'PASS: safe R36H diagnostics, bad ELF detected, no browser or firmware execution'
