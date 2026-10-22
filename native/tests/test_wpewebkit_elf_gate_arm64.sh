#!/bin/bash
# Validate the WPE ELF audit CLI against real ARM64 fixture shared objects.
# These are tiny fakes, not a WebKit engine or a runnable R36H browser.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
auditor="$root/scripts/verify-built-wpewebkit.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
readelf -h "$(command -v bash)" | grep -Eq 'Machine:.*AArch64'
cat > "$tmp/good.c" <<'EOF'
#include <stdio.h>
int webkit_web_view_get_wpe_view(void) { return puts("wpe test export"); }
EOF
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 "$tmp/good.c" \
 -o "$tmp/libWPEWebKit-2.0.so.1"
python3 "$auditor" --library "$tmp/libWPEWebKit-2.0.so.1" \
 --report "$tmp/good-result.txt" > /dev/null
grep -Fxq 'WPE_LIBRARY_ELF_AUDIT=PASS_STATIC_AARCH64' "$tmp/good-result.txt"
grep -Fxq 'WPE_PLATFORM_EXPORT_PRESENT=true' "$tmp/good-result.txt"
grep -Fxq 'WPE_MEDIA_FREE=true' "$tmp/good-result.txt"
# Refuse a correct ELF with a build-host absolute RUNPATH.
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 \
 -Wl,-rpath,/home/runner/work/Fire4nix/Fire4nix/tmp \
 "$tmp/good.c" -o "$tmp/libWPEWebKit-2.0.so.1"
if python3 "$auditor" --library "$tmp/libWPEWebKit-2.0.so.1" \
 --report "$tmp/invalid-runpath.txt" > /dev/null; then
 echo 'FAIL: unrelocatable RUNPATH accepted' >&2; exit 1
fi
grep -Fq 'NONRELOCATABLE_RPATH' "$tmp/invalid-runpath.txt"
# Refuse libWPEWebKit stub with the required entrypoint unresolved.
cat > "$tmp/undefined.c" <<'EOF'
#include <stdio.h>
extern int GST_CAT_DEFAULT;
int webkit_web_view_get_wpe_view(void) {
  return puts("wpe") + GST_CAT_DEFAULT;
}
EOF
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 "$tmp/undefined.c" \
 -o "$tmp/libWPEWebKit-2.0.so.1"
if python3 "$auditor" --library "$tmp/libWPEWebKit-2.0.so.1" \
 --report "$tmp/undefined-gst.txt" > /dev/null; then
 echo 'FAIL: undefined GST_CAT_DEFAULT accepted' >&2; exit 1
fi
grep -Fq 'UNDEFINED_GST_CAT_DEFAULT' "$tmp/undefined-gst.txt"
echo 'WPE_LINKED_LIBRARY_ARM64_FIXTURES=PASS_REAL_ELF_GATE'
