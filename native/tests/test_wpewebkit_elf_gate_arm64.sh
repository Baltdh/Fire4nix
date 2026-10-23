#!/bin/bash
# Validate the WPE ELF audit CLI against real ARM64 fixture shared objects.
# These are tiny fakes, not a WebKit engine or a runnable R36H browser.
set -euo pipefail
# Print the failed test command (only synthetic ELF fixtures are handled).
trap 'echo "WPE_CORE_ARM64_FIXTURE_FAILED_AT_LINE=$LINENO COMMAND=$BASH_COMMAND" >&2' ERR
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
# Recreate the GCC15 failure as a real AArch64 ELF with undefined
# __aarch64_ldadd4_relax and no runtime provider.
# GCC recognizes the helper name as its own outlined-atomic runtime
# function and rewrites a direct C declaration into a __getauxval call.
# A data relocation in ARM64 assembly creates the *real* unresolved dynsym.
cat > "$tmp/outlined.S" <<'EOF'
.data
.global synthetic_outlined_atomic_reference
synthetic_outlined_atomic_reference:
  .xword __aarch64_ldadd4_relax
.section .note.GNU-stack,"",%progbits
EOF
# Avoid implicit libgcc: the ARM64 host compiler resolves special
# __aarch64_* helpers itself, concealing exactly the dangling ABI to test.
# Explicit -lc still supplies real DT_NEEDED for the shared object.
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEWebKit-2.0.so.1 \
 "$tmp/good.c" "$tmp/outlined.S" -lc -o "$tmp/libWPEWebKit-2.0.so.1"
readelf --wide --dyn-syms "$tmp/libWPEWebKit-2.0.so.1" > "$tmp/outlined-symbols.txt"
if ! grep -Fq '__aarch64_ldadd4_relax' "$tmp/outlined-symbols.txt"; then
 echo 'ERROR: synthetic GCC15 undefined symbol not present in ARM64 dynsym:' >&2
 sed -n '1,75p' "$tmp/outlined-symbols.txt" >&2
 exit 8
fi
if python3 "$auditor" --library "$tmp/libWPEWebKit-2.0.so.1" \
 --report "$tmp/outlined-fail.txt" >/dev/null; then
 echo 'FAIL: undefined GCC15 AArch64 outlined atomic accepted' >&2; exit 1
fi
grep -Fxq 'WPE_GCC15_UNDEFINED_OUTLINED_COUNT=1' "$tmp/outlined-fail.txt"
grep -Fq 'UNDEFINED_GCC15_OUTLINED_ATOMICS' "$tmp/outlined-fail.txt"

# GCC still legitimately needs libatomic.so.1 for 128-bit operations:
# if an ELF retains __atomic_load_16 without DT_NEEDED, fail it.
cat > "$tmp/unprovided-atomic.S" <<'EOF'
.data
.global synthetic_unprovided_atomic16_reference
synthetic_unprovided_atomic16_reference:
  .xword __atomic_load_16
.section .note.GNU-stack,"",%progbits
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEWebKit-2.0.so.1 \
 "$tmp/good.c" "$tmp/unprovided-atomic.S" -lc -o "$tmp/libWPEWebKit-2.0.so.1"
if python3 "$auditor" --library "$tmp/libWPEWebKit-2.0.so.1" \
 --report "$tmp/atomic16-fail.txt" >/dev/null; then
 echo 'FAIL: unresolved 128-bit atomic without libatomic provider accepted' >&2; exit 1
fi
grep -Fq 'MISSING_LIBATOMIC16_DT_NEEDED' "$tmp/atomic16-fail.txt"

echo 'WPE_LINKED_LIBRARY_ARM64_FIXTURES=PASS_REAL_ELF_GATE'
