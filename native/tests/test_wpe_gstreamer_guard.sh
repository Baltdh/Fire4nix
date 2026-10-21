#!/bin/sh
# CI unit test only. Creates tiny host ELF fixtures, not a ROCKNIX browser.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
AUDITOR="$ROOT/rocknix-integration/audit-wpe-gstreamer.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' 0 HUP INT TERM
mkdir -p "$T/rt/lib"
LIB="$T/rt/lib/libgstvideo-1.0.so.0"
# Missing module-local category must fail strict packaging.
printf 'extern void *GST_CAT_DEFAULT; void *gst_test(void){ return GST_CAT_DEFAULT; }\n' | cc -shared -fPIC -x c - -o "$LIB"
FIRE4NIX_GST_REPORT="$T/report.txt" sh "$AUDITOR" --audit "$T/rt" > "$T/audit.log"
grep -q '^UNRESOLVED_GST_CAT_DEFAULT=libgstvideo-1.0.so.0$' "$T/report.txt"
grep -q '^status=BLOCK_GST_ABI$' "$T/report.txt"
set +e
FIRE4NIX_GST_REPORT="$T/strict.txt" sh "$AUDITOR" --strict "$T/rt" > "$T/strict.log"
rc=$?
set -e
test "$rc" -eq 6
grep -q '^status=BLOCK_GST_ABI$' "$T/strict.txt"
# A correctly linked minimal library is permitted without executing it.
printf 'static void *GST_CAT_DEFAULT; void *gst_test(void){return GST_CAT_DEFAULT;}\n' | cc -shared -fPIC -x c - -o "$LIB"
FIRE4NIX_GST_REPORT="$T/clean.txt" sh "$AUDITOR" --strict "$T/rt" > /dev/null
grep -q '^status=STATIC_GST_SYMBOL_CHECK_PASS$' "$T/clean.txt"
ln -s libgstvideo-1.0.so.0 "$T/rt/lib/libgstvideo-1.0.so"
FIRE4NIX_GST_REPORT="$T/symlink.txt" sh "$AUDITOR" --strict "$T/rt" > /dev/null
grep -q '^gst_libraries_checked=1$' "$T/symlink.txt"
# The audit must also detect placeholder/corrupt ELF.
printf 'not-an-elf' > "$T/rt/lib/libgstvideo-1.0.so.0"
set +e
FIRE4NIX_GST_REPORT="$T/invalid.txt" sh "$AUDITOR" --strict "$T/rt" > /dev/null
rc=$?
set -e
test "$rc" -eq 6
grep -q '^BROKEN_ELF=libgstvideo-1.0.so.0$' "$T/invalid.txt"
# A renamed non-libgst library must not bypass the ABI guard.
rm -f "$T/rt/lib/libgstvideo-1.0.so" "$LIB"
printf 'extern void *GST_CAT_DEFAULT; void *webkit_test(void){ return GST_CAT_DEFAULT; }\n' | cc -shared -fPIC -x c - -o "$T/rt/lib/libWPEWebKit-2.0.so.1"
set +e
FIRE4NIX_GST_REPORT="$T/renamed.txt" sh "$AUDITOR" --strict "$T/rt" > /dev/null
rc=$?
set -e
test "$rc" -eq 6
grep -Fq 'UNRESOLVED_GST_CAT_DEFAULT=libWPEWebKit-2.0.so.1' "$T/renamed.txt"
# WPE executable helpers are also covered by the static scanner.
rm -f "$T/rt/lib/libWPEWebKit-2.0.so.1"
mkdir -p "$T/rt/libexec/wpe-webkit-2.0"
# Shared-object fixture with a subprocess filename: audit uses ELF metadata only.
printf 'extern void *GST_CAT_DEFAULT; int main(void){return GST_CAT_DEFAULT != 0;}\n' | cc -shared -fPIC -x c - -o "$T/rt/libexec/wpe-webkit-2.0/WPEWebProcess"
set +e
FIRE4NIX_GST_REPORT="$T/helper.txt" sh "$AUDITOR" --strict "$T/rt" > /dev/null
rc=$?
set -e
test "$rc" -eq 6
grep -Fq 'UNRESOLVED_GST_CAT_DEFAULT=WPEWebProcess' "$T/helper.txt"
# Both supported runtime inputs (root and root/lib) locate the same helper.
set +e
FIRE4NIX_GST_REPORT="$T/helper-from-lib.txt" sh "$AUDITOR" --strict "$T/rt/lib" > /dev/null
rc=$?
set -e
test "$rc" -eq 6
grep -Fq 'UNRESOLVED_GST_CAT_DEFAULT=WPEWebProcess' "$T/helper-from-lib.txt"
echo 'PASS: GStreamer ABI audit includes renamed WPE libraries and helpers'
