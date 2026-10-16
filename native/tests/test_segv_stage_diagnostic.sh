#!/bin/sh
# Check R36H SIGSEGV diagnosis with fake ABI commands; never run real WPE.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/pkg/Fire4Nix/bin" "$T/runtime/lib"
cp "$ROOT/installer/Diagnosticar-Fire4Nix.sh" "$T/pkg/Diagnosticar-Fire4Nix.sh"
printf 'mock-WPE' > "$T/runtime/lib/libWPEWebKit-2.0.so.1"
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
grep -q '^WPE_dynamic_dependencies=skipped_in_safe_mode_no_loader
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/safe-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/dlopen.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --screen > "$T/dlopen-screen.txt"
grep -q '^WPEPlatform_preflight_exit=139$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault=SIGSEGV_in_preflight$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault_stage=during_dlopen_or_its_dependencies$' "$T/dlopen.txt"
grep -q '\[FIRE4NIX-NATIVE\] dlopen libWPEWebKit-2.0.so.1' "$T/dlopen.txt"
grep -q 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies' "$T/dlopen-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_MOCK_SEGFAULT_STAGE=after \
 FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/after.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh"
grep -q '^WPEPlatform_fault_stage=after_dlopen_success$' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_begin' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_end' "$T/after.txt"
echo 'PASS: safe inspection never loads WPE; code 139 attributed to native checkpoint and preserved for photos'
 "$T/safe.txt"
grep -q '^SAFE_MODE_NOTE=readelf_only_without_ldd_or_WPE_execution
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/safe-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/dlopen.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --screen > "$T/dlopen-screen.txt"
grep -q '^WPEPlatform_preflight_exit=139$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault=SIGSEGV_in_preflight$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault_stage=during_dlopen_or_its_dependencies$' "$T/dlopen.txt"
grep -q '\[FIRE4NIX-NATIVE\] dlopen libWPEWebKit-2.0.so.1' "$T/dlopen.txt"
grep -q 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies' "$T/dlopen-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_MOCK_SEGFAULT_STAGE=after \
 FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/after.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh"
grep -q '^WPEPlatform_fault_stage=after_dlopen_success$' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_begin' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_end' "$T/after.txt"
echo 'PASS: safe inspection never loads WPE; code 139 attributed to native checkpoint and preserved for photos'
 "$T/safe.txt"
grep -q '^WPEPlatform_preflight=skipped_safe_mode_no_library_execution
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/safe-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/dlopen.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --screen > "$T/dlopen-screen.txt"
grep -q '^WPEPlatform_preflight_exit=139$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault=SIGSEGV_in_preflight$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault_stage=during_dlopen_or_its_dependencies$' "$T/dlopen.txt"
grep -q '\[FIRE4NIX-NATIVE\] dlopen libWPEWebKit-2.0.so.1' "$T/dlopen.txt"
grep -q 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies' "$T/dlopen-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_MOCK_SEGFAULT_STAGE=after \
 FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/after.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh"
grep -q '^WPEPlatform_fault_stage=after_dlopen_success$' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_begin' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_end' "$T/after.txt"
echo 'PASS: safe inspection never loads WPE; code 139 attributed to native checkpoint and preserved for photos'
 "$T/safe.txt"
grep -q 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution' "$T/safe-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
 FIRE4NIX_DIAGNOSTIC_OUT="$T/dlopen.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh" --screen > "$T/dlopen-screen.txt"
grep -q '^WPEPlatform_preflight_exit=139$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault=SIGSEGV_in_preflight$' "$T/dlopen.txt"
grep -q '^WPEPlatform_fault_stage=during_dlopen_or_its_dependencies$' "$T/dlopen.txt"
grep -q '\[FIRE4NIX-NATIVE\] dlopen libWPEWebKit-2.0.so.1' "$T/dlopen.txt"
grep -q 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies' "$T/dlopen-screen.txt"

FIRE4NIX_MOCK_CALLS="$T/calls" FIRE4NIX_MOCK_SEGFAULT_STAGE=after \
 FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" FIRE4NIX_DIAGNOSTIC_OUT="$T/after.txt" \
 sh "$T/pkg/Diagnosticar-Fire4Nix.sh"
grep -q '^WPEPlatform_fault_stage=after_dlopen_success$' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_begin' "$T/after.txt"
grep -q 'WPEPlatform_native_checkpoints_end' "$T/after.txt"
echo 'PASS: safe inspection never loads WPE; code 139 attributed to native checkpoint and preserved for photos'
