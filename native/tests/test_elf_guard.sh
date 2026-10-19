#!/bin/sh
# Offline test: no browser, no network, no changes outside private temp fixtures.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/runtime/lib" "$T/runtime/libexec/wpe-webkit-2.0"
LIB="$T/runtime/lib/libWPEWebKit-2.0.so.1"
run_check() {
  FIRE4NIX_ELF_FILE="$LIB" FIRE4NIX_ELF_REPORT="$T/out.txt" \
    sh "$ROOT/installer/Fire4Nix-Inspecionar-ELF.sh" "$@" > "$T/stdout.txt"
}
printf 'MOCK-lib\n' > "$LIB"
run_check --quick
grep -q '^webkit_lib_format=unknown_non_ELF$' "$T/out.txt"
grep -q '^webkit_lib_verdict=BLOCK_NON_ELF$' "$T/out.txt"
grep -q '^sha256_whole_library=skipped_quick_mode$' "$T/out.txt"
grep -q '^webkit_executed=no$' "$T/out.txt"
printf '\037\213\010fake' > "$LIB"
run_check --quick
grep -q '^webkit_lib_format=gzip_not_ELF$' "$T/out.txt"
printf '\177ELF' > "$LIB"
run_check --quick
grep -q '^webkit_lib_format=ELF_magic$' "$T/out.txt"
grep -q '^webkit_lib_verdict=ELF_MAGIC_PRESENT_OTHER_ABI_CHECKS_REQUIRED$' "$T/out.txt"
printf 'version https://git-lfs.github.com/spec/v1\n' > "$LIB"
run_check --quick
grep -q '^webkit_lib_format=git_lfs_pointer_not_ELF$' "$T/out.txt"
printf '<html>an error</html>' > "$LIB"
run_check --quick
grep -q '^webkit_lib_format=html_not_ELF$' "$T/out.txt"
rm -f "$LIB"
ln -s "missing-target.so" "$LIB"
run_check --quick
grep -q '^webkit_lib_status=broken_symlink$' "$T/out.txt"
rm -f "$LIB"
printf 'mock library\n' > "$LIB"
run_check --hash
grep -q '^sha256_whole_library_begin$' "$T/out.txt"
grep -q '^sha256_whole_library_end$' "$T/out.txt"
# GNU CI runners exist in both ARM64 and x86_64 variants.
cp /bin/ls "$T/runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
run_check --quick
grep -q '^WPEWebProcess_status=present$' "$T/out.txt"
grep -q '^WPEWebProcess_format=ELF_magic$' "$T/out.txt"
grep -Eq '^WPEWebProcess_architecture=(aarch64|x86_64_NOT_R36H|unknown)$' "$T/out.txt"
# Missing runtime produces a report instead of executing any binary.
FIRE4NIX_ELF_FILE="$T/missing/lib/libWPEWebKit-2.0.so.1" \
  FIRE4NIX_ELF_REPORT="$T/none.txt" \
  sh "$ROOT/installer/Fire4Nix-Inspecionar-ELF.sh" --quick > /dev/null
grep -q '^webkit_lib_status=not_found$' "$T/none.txt"
echo 'PASS: ELF magic, compressed placeholders, symlinks, subprocesses and optional hash'
