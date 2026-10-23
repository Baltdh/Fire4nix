#!/usr/bin/env bash
# Execute only on Ubuntu native AArch64. The fixtures are not WebKit binaries.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dir="$tmp/download/compiled-target-evidence"
mkdir -p "$dir" "$tmp/reports"
test "$(uname -m)" = aarch64

cat > "$tmp/wpe.c" <<'EOF'
int webkit_web_view_get_wpe_view(void) { return 7; }
EOF
cc -shared -fPIC -Wl,-soname,libWPEWebKit-2.0.so.1 \
  "$tmp/wpe.c" -o "$dir/libWPEWebKit-2.0.so.1"

cat > "$tmp/process.c" <<'EOF'
int main(void) { return 0; }
EOF
for process in WPEWebProcess WPENetworkProcess; do
  cc -fPIE -pie "$tmp/process.c" -o "$dir/$process"
  readelf -h "$dir/$process" | grep -Eq 'Machine:[[:space:]]+AArch64'
done
readelf -h "$dir/libWPEWebKit-2.0.so.1" | grep -Eq 'Machine:[[:space:]]+AArch64'

python3 "$root/scripts/audit-real-fourcc-wpe-artifacts.py" \
  --artifact "$tmp/download" \
  --report "$tmp/reports/accepted.txt" --build-conclusion success
grep -Fxq 'WPE_LINKED_AND_PROCESSES_STATUS=PASS_STATIC_ONLY_NOT_DEVICE_ABI' "$tmp/reports/accepted.txt"
grep -Fxq 'R36H_INSTALLABLE=no' "$tmp/reports/accepted.txt"
# A result from a genuinely failed build must not be promoted even if it
# happens to include all three ELF files.
python3 "$root/scripts/audit-real-fourcc-wpe-artifacts.py" \
  --artifact "$tmp/download" --report "$tmp/reports/failed-build.txt" \
  --build-conclusion failure
grep -Fxq 'WPE_LINKED_AND_PROCESSES_STATUS=BLOCKED_OR_INCOMPLETE' "$tmp/reports/failed-build.txt"

# Genuine AArch64 executable can still request a foreign x86_64 dynamic
# loader; this must fail the artifact gate before deploy.
cc -fPIE -pie -Wl,--dynamic-linker,/lib64/ld-linux-x86-64.so.2 \
  "$tmp/process.c" -o "$dir/WPEWebProcess"
if python3 "$root/scripts/audit-real-fourcc-wpe-artifacts.py" \
  --artifact "$tmp/download" --report "$tmp/reports/foreign-loader.txt" \
  --build-conclusion success; then
  echo 'ERROR: executable using x86_64 ELF interpreter was accepted' >&2; exit 1
fi
grep -Fq 'FOREIGN_PT_INTERP:/lib64/ld-linux-x86-64.so.2' \
  "$tmp/reports/foreign-loader.txt"

# A host-CI path encoded into any subprocess must be blocked.
cc -fPIE -pie -Wl,-rpath,/home/runner/work/Fire4nix/tmp \
  "$tmp/process.c" -o "$dir/WPEWebProcess"
if python3 "$root/scripts/audit-real-fourcc-wpe-artifacts.py" \
  --artifact "$tmp/download" --report "$tmp/reports/unsafe.txt" \
  --build-conclusion success; then
  echo 'ERROR: build-host RUNPATH accepted' >&2; exit 1
fi
grep -Fq 'UNSAFE_RUNPATH' "$tmp/reports/unsafe.txt"

# Missing a real network helper also blocks a would-be successful build.
rm "$dir/WPENetworkProcess"
if python3 "$root/scripts/audit-real-fourcc-wpe-artifacts.py" \
  --artifact "$tmp/download" --report "$tmp/reports/missing.txt" \
  --build-conclusion success; then
  echo 'ERROR: missing network process accepted' >&2; exit 1
fi
grep -Fq 'WPENetworkProcess:MISSING' "$tmp/reports/missing.txt"
echo 'REAL_AARCH64_WPE_PROCESS_ARTIFACT_FIXTURES=PASS_NO_R36H_EXECUTION'
