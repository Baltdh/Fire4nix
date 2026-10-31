#!/bin/sh
# Regression: local HTML must bypass a missing text/html MIME association.
set -eu
source_file=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)/fire4nix_wpeplatform.cpp
grep -Fq 'using LoadHtml = void (*)(gpointer, const char*, const char*);' "$source_file"
grep -Fq 'symbol<LoadHtml>(app.webkit, "webkit_web_view_load_html")' "$source_file"
grep -Fq 'g_filename_from_uri(url, &hostname, &fileError)' "$source_file"
grep -Fq 'g_file_get_contents(localPath, &html, &htmlLength, &fileError)' "$source_file"
grep -Fq 'app.loadHtml(app.view, html, url)' "$source_file"
grep -Fq 'preserving the original file URI as base' "$source_file"
test_script=$(CDPATH= cd -- "$(dirname -- "$0")/../../installer" && pwd -P)/Fire4Nix-Primeiro-Teste-R36.sh
grep -Fq 'REPORT=$(mktemp "$REPORT_DIR/Primeiro-Teste-R36H-XXXXXX")' "$test_script"
if grep -Fq 'Primeiro-Teste-R36H-XXXXXX.txt' "$test_script"; then
  echo 'FAIL: non-portable mktemp suffix remains in R36H preflight script' >&2
  exit 1
fi
echo 'PASS: local HTML MIME fallback and BusyBox-compatible mktemp template.'
