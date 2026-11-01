#!/bin/sh
# Check R36H SIGSEGV diagnosis with fake ABI commands; never run real WPE.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/pkg/Fire4Nix/bin" "$T/runtime/lib"
cp "$ROOT/installer/Diagnosticar-Fire4Nix.sh" "$T/pkg/Diagnosticar-Fire4Nix.sh"
python3 - "$T/runtime/lib/libWPEWebKit-2.0.so.1" "$T/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" "$T/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" <<'PY'
import struct
import sys

for path in sys.argv[1:]:
    ehdr = bytearray(64)
    ehdr[:7] = b"\\x7fELF\\x02\\x01\\x01"
    struct.pack_into("<HHI", ehdr, 16, 3, 183, 1)
    struct.pack_into("<Q", ehdr, 32, 64)
    struct.pack_into("<HHHHHH", ehdr, 52, 64, 56, 2, 0, 0, 0)
    phdrs = bytearray(112)
    struct.pack_into("<IIQQQQQQ", phdrs, 0, 1, 5, 0, 0, 0, 192, 192, 4096)
    struct.pack_into("<IIQQQQQQ", phdrs, 56, 2, 6, 176, 176, 176, 16, 16, 8)
    with open(path, "wb") as stream:
        stream.write(ehdr)
        stream.write(phdrs)
        stream.write(struct.pack("<qQ", 0, 0))
PY
cat > "$T/runtime/BUILD-REPORT.txt" <<'REPORT'
GPU_PROCESS_PROFILE=disabled_verified_wayland
ENABLE_BUBBLEWRAP_SANDBOX=OFF
REPORT
cat > "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64" <<'NATIVE'
#!/bin/sh
echo called >> "$FIRE4NIX_MOCK_CALLS"
printf '[FIRE4NIX-NATIVE] dlopen libWPEWebKit-2.0.so.1\n' >&2
case "${FIRE4NIX_MOCK_SEGFAULT_STAGE:-}" in
  after) printf '[FIRE4NIX-NATIVE] dlopen success\n' >&2 ;;
esac
exit 139
NATIVE
chmod +x "$T/pkg/Fire4Nix/bin/fire4nix-native-aarch64"
: > "$T/calls"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/safe.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --safe > "$T/safe-screen.txt"
test ! -s "$T/calls"
grep -q '^WPE_dynamic_dependencies=skipped_in_safe_mode_no_loader$' "$T/safe.txt"
grep -q '^SAFE_MODE_NOTE=readelf_only_without_ldd_or_WPE_execution$' "$T/safe.txt"
grep -q '^WPEPlatform_preflight=skipped_safe_mode_no_library_execution$' "$T/safe.txt"
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/safe-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/dlopen.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --screen > "$T/dlopen-screen.txt"
grep -q '^WPEPlatform_preflight_exit=139$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault=SIGSEGV_in_preflight$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault_stage=during_dlopen_or_its_dependencies$' "$T/dlopen.txt"
grep -Fq '[FIRE4NIX-NATIVE] dlopen libWPEWebKit-2.0.so.1' "$T/dlopen.txt"
grep -q 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies' "$T/dlopen-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_MOCK_SEGFAULT_STAGE=after \
 FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/after.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh"
grep -q '^WPEPlatform_fault_stage=after_dlopen_success$' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_begin' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_end' "$T/after.txt"
echo 'PASS: safe inspection never loads WPE; code 139 attributed to native checkpoint and preserved for photos'
