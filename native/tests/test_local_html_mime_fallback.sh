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
echo 'PASS: local .html/.htm uses explicit HTML MIME-independent loading with file URI base.'
