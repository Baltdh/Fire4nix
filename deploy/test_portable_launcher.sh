#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    echo "FAIL: portable launcher/ABI test exit code $result" >&2
    for log in "$tmp/diagnostic-report.log" "$tmp/incompatible-report.log" "$tmp/incompatible-console.log" "$tmp/compatible-report.log" "$tmp/compatible-console.log"; do
      if [ -f "$log" ]; then
        echo "--- $log ---" >&2
        tail -100 "$log" >&2
      fi
    done
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/external/downloads/Fire4Nix" "$tmp/data"
cp "$root/deploy/Fire4Nix-ROCKNIX.sh" "$tmp/external/downloads/Fire4Nix/Start.sh"
cat > "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" <<'EOF'
#!/bin/sh
printf 'PORTABLE_TEST_OK %s\n' "$PWD"
EOF
chmod +x "$tmp/external/downloads/Fire4Nix/Start.sh"
log="$tmp/launch.log"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" \
  "$tmp/external/downloads/Fire4Nix/Start.sh"
grep -F 'PORTABLE_TEST_OK' "$log"
grep -F 'Browser exit code: 0' "$log"
ln -s "$tmp/external/downloads/Fire4Nix/Start.sh" "$tmp/shortcut.sh"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/shortcut.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" = 2
mkdir -p "$tmp/override"
cp "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" "$tmp/override/Fire4Nix.sh"
FIRE4NIX_APP_DIR="$tmp/override" FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/shortcut.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" = 3
# Exercise the requested ROCKNIX Tools layout, including diagnostic auto-discovery.
mkdir -p "$tmp/Tools/Fire4Nix"
cp "$root/deploy/Fire4Nix-ROCKNIX.sh" "$tmp/Tools/Fire4Nix/Start.sh"
cp "$root/deploy/Fire4Nix-WPE-Diagnostico.sh" "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh"
cp "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" "$tmp/Tools/Fire4Nix/Fire4Nix.sh"
chmod +x "$tmp/Tools/Fire4Nix/Start.sh"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/Tools/Fire4Nix/Start.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" -eq 4
env -u FIRE4NIX_APP_DIR FIRE4NIX_DIAGNOSTIC_LOG="$tmp/diagnostic-report.log" \
  sh "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh" > "$tmp/diagnostic.log"
grep -F "app: $tmp/Tools/Fire4Nix" "$tmp/diagnostic.log"
grep -F "app: $tmp/Tools/Fire4Nix" "$tmp/diagnostic-report.log"
grep -F "Diagnostic saved: $tmp/diagnostic-report.log" "$tmp/diagnostic.log"
test "$(stat -c '%a' "$tmp/diagnostic-report.log")" = 600
# ABI preflight is read-only: simulate a device with too-old glibc and verify
# that it reports incompatible symbol requirements, rather than claiming the
# standalone launcher will run on ROCKNIX.
mkdir -p "$tmp/Tools/Fire4Nix/bin" "$tmp/mock-bin"
printf '%s\n' 'libc.so.6' 'libfire4nix-does-not-exist.so.999' > "$tmp/Tools/WPE-CORE-NEEDED.txt"
printf '%s\n' 'libc.so.6' 'libfire4nix-does-not-exist.so.999' 'libfire4nix-transitive-missing.so.999' > "$tmp/Tools/WPE-CORE-ALL-NEEDED.txt"
printf '%s\n' '{"highest_required_glibc_across_components": "GLIBC_9.99", "highest_required_cpp_abi_across_components": {"GLIBCXX":"GLIBCXX_99.99.99", "CXXABI":"CXXABI_99.99.99"}}' > "$tmp/Tools/WPE-ABI-REQUIREMENTS.json"
cp /bin/true "$tmp/Tools/Fire4Nix/bin/fire4nix-wpe-platform"
cat > "$tmp/mock-bin/bwrap" <<'BWRAP'
#!/bin/sh
echo 'Operation not permitted' >&2
exit 77
BWRAP
chmod +x "$tmp/mock-bin/bwrap"
cat > "$tmp/mock-bin/getconf" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = GNU_LIBC_VERSION ]; then printf 'glibc %s\n' "${FIRE4NIX_TEST_LIBC_VERSION:-2.0}"; else exit 1; fi
MOCK
chmod +x "$tmp/mock-bin/getconf"
PATH="$tmp/mock-bin:$PATH" FIRE4NIX_DIAGNOSTIC_LOG="$tmp/incompatible-report.log" \
  sh "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh" > "$tmp/incompatible-console.log"
grep -F 'WPE build-origin GLIBC floor: GLIBC_9.99' "$tmp/incompatible-report.log"
grep -F 'WPE build-origin GLIBCXX requirement: GLIBCXX_99.99.99' "$tmp/incompatible-report.log"
grep -F 'WPE build-origin CXXABI requirement: CXXABI_99.99.99' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: WPE build requires GLIBC_9.99 but device reports glibc 2.0' "$tmp/incompatible-report.log"
grep -F 'libfire4nix-does-not-exist.so.999: NOT FOUND in common paths' "$tmp/incompatible-report.log"
grep -F 'libfire4nix-transitive-missing.so.999: NOT FOUND in common paths' "$tmp/incompatible-report.log"
grep -F 'WPE Core direct and transitive SONAMEs not located in common paths: 2' "$tmp/incompatible-report.log"
grep -F 'WPE Bubblewrap namespace preflight: FAIL (exit 77)' "$tmp/incompatible-report.log"
grep -F 'WARNING: sandboxed WebKit subprocess startup remains unverified' "$tmp/incompatible-report.log"
grep -F 'Device highest GLIBCXX:' "$tmp/incompatible-report.log"
grep -F 'Device highest CXXABI:' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: WPE build requires GLIBCXX_99.99.99' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: WPE build requires CXXABI_99.99.99' "$tmp/incompatible-report.log"
grep -F 'Highest required GLIBC: GLIBC_' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: binary requires GLIBC_' "$tmp/incompatible-report.log"
grep -F 'WPEWebProcess: NOT FOUND' "$tmp/incompatible-report.log"
# Positive control: use an intentionally newer device libc and low
# symbol requirements. This also guards against lexicographic comparisons.
printf '%s\n' '{"highest_required_glibc_across_components":"GLIBC_2.38","highest_required_cpp_abi_across_components":{"GLIBCXX":"GLIBCXX_1.0","CXXABI":"CXXABI_1.0"}}' > "$tmp/Tools/WPE-ABI-REQUIREMENTS.json"
FIRE4NIX_TEST_LIBC_VERSION=99.0 PATH="$tmp/mock-bin:$PATH" \
  FIRE4NIX_DIAGNOSTIC_LOG="$tmp/compatible-report.log" \
  sh "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh" > "$tmp/compatible-console.log"
grep -F 'WPE build GLIBC requirement: satisfied' "$tmp/compatible-report.log"
grep -F 'WPE GLIBCXX requirement: satisfied' "$tmp/compatible-report.log"
grep -F 'WPE CXXABI requirement: satisfied' "$tmp/compatible-report.log"
if grep -Fq 'INCOMPATIBLE:' "$tmp/compatible-report.log"; then
  echo 'FAIL: compatible build reported incompatible' >&2
  exit 1
fi
echo 'Portable, Tools and ABI compatibility diagnostics passed'
