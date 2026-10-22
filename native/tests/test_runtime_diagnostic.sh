#!/bin/sh
# Offline smoke tests for dual-SD WPE discovery and photo-friendly output.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/package/Fire4Nix/bin" "$T/runtime/libexec/wpe-webkit-2.0" "$T/runtime/lib"
cp "$ROOT/installer/Diagnosticar-Fire4Nix.sh" "$T/package/Diagnosticar-Fire4Nix.sh"
cat > "$T/package/Fire4Nix/bin/fire4nix-native-aarch64" <<'BROWSER'
#!/bin/sh
printf '[FIRE4NIX-ABI] wpe_version=2.54.1\n'
printf '[FIRE4NIX-ABI] webkit_library=mocked\n'
printf '[FIRE4NIX-ABI] wpe_toplevel_fullscreen=absent\n'
exit 78
BROWSER
chmod +x "$T/package/Fire4Nix/bin/fire4nix-native-aarch64"
printf 'MOCK-lib' > "$T/runtime/lib/libWPEWebKit-2.0.so.1"
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'MOCK-process' > "$T/runtime/libexec/wpe-webkit-2.0/$p"
done
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/found.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --screen > "$T/screen.txt"
grep -q '^WPE_library=present$' "$T/found.txt"
grep -q '^WPEWebProcess=present$' "$T/found.txt"
grep -q '^WPENetworkProcess=present$' "$T/found.txt"
grep -q '^WPEGPUProcess=present$' "$T/found.txt"
grep -q '^WPE_version=2.54.1$' "$T/found.txt"
grep -q '^WPEPlatform_preflight_exit=78$' "$T/found.txt"
grep -q '^WPEPlatform_preflight_note=legacy_library_without_new_API$' "$T/found.txt"
grep -q '\[FIRE4NIX-ABI\] wpe_toplevel_fullscreen=absent' "$T/found.txt"
grep -q 'RESUMO PARA FOTO' "$T/screen.txt"
grep -q 'WPE_version=2.54.1' "$T/screen.txt"
grep -q 'WPEPlatform_preflight_exit=78' "$T/screen.txt"
grep -q 'GRAPHICS_STATUS=NOT_VERIFIED_BY_PREFLIGHT' "$T/screen.txt"
# Valid GPU-off build reports should not be shown as a missing required helper.
rm "$T/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$T/runtime/BUILD-REPORT.txt"
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/gpu-off.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --screen > "$T/gpu-off-screen.txt"
grep -Fxq 'gpu_runtime_profile=disabled_verified_wayland' "$T/gpu-off.txt"
grep -Fxq 'gpu_process_required=0' "$T/gpu-off.txt"
grep -Fxq 'WPEGPUProcess=not_required_verified_wayland' "$T/gpu-off.txt"
grep -Fq 'WPEGPUProcess=not_required_verified_wayland' "$T/gpu-off-screen.txt"
grep -Fq 'gpu_process_required=0' "$T/gpu-off-screen.txt"
# Unknown or contradictory report must fail closed in the diagnosis too.
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\nGPU_PROCESS_PROFILE=enabled_verified\n' \
  > "$T/runtime/BUILD-REPORT.txt"
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/conflict.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --safe >/dev/null
grep -Fxq 'gpu_runtime_profile=invalid_report_requires_gpu' "$T/conflict.txt"
grep -Fxq 'gpu_process_required=1' "$T/conflict.txt"
grep -Fxq 'WPEGPUProcess=missing' "$T/conflict.txt"
rm "$T/runtime/BUILD-REPORT.txt"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$T/outside.txt"
ln -s "$T/outside.txt" "$T/runtime/BUILD-REPORT.txt"
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/link.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --safe >/dev/null
grep -Fxq 'gpu_runtime_profile=invalid_report_requires_gpu' "$T/link.txt"
grep -Fxq 'WPEGPUProcess=missing' "$T/link.txt"
rm "$T/runtime/BUILD-REPORT.txt"
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/runtime" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/legacy.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --safe >/dev/null
grep -Fxq 'gpu_runtime_profile=legacy_requires_gpu' "$T/legacy.txt"
grep -Fxq 'gpu_process_required=1' "$T/legacy.txt"
grep -Fxq 'WPEGPUProcess=missing' "$T/legacy.txt"
# When run directly from an extracted package on SD2, no local runtime
# should be mistaken for a functioning graphics engine.
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/nonexistent" \
  FIRE4NIX_DIAGNOSTIC_OUT="$T/missing.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --screen > "$T/missing-screen.txt"
grep -q '^WPE_library=missing$' "$T/missing.txt"
grep -q '^WPE_runtime_source=not_found_on_checked_SD_paths$' "$T/missing.txt"
# Binary exists in the extracted package; the library does not.
grep -q '^WPEPlatform_preflight=skipped_runtime_missing_no_launcher$' "$T/missing.txt"
echo "PASS: dual-SD override, external WPE library, legacy status 78, screen-friendly report and missing-runtime distinction"
