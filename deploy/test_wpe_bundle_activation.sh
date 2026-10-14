#!/usr/bin/env bash
# Simulate a prospective AArch64 portable runtime without ever executing
# its synthetic ELF processes. Works on both x86_64 and ARM64 CI runners.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    echo "FAIL: portable WPE runtime test exit code $result" >&2
    for log in "$TMP"/*.log; do
      [ -f "$log" ] || continue
      echo "--- $log ---" >&2
      cat "$log" >&2
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/app" "$TMP/bundle/lib" "$TMP/bundle/libexec/wpe-webkit-2.0"

# The ELF header has the correct target architecture but the fixture is
# deliberately non-executable on x86_64 and never invoked on either runner.
for file in \
  "$TMP/bundle/lib/libWPEWebKit-2.0.so" \
  "$TMP/bundle/libexec/wpe-webkit-2.0/WPEWebProcess" \
  "$TMP/bundle/libexec/wpe-webkit-2.0/WPENetworkProcess" \
  "$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess"; do
  cp /bin/true "$file"
  printf '\267\000' | dd of="$file" bs=1 seek=18 conv=notrunc 2>/dev/null
  chmod +x "$file"
done

write_manifest() {
  (cd "$TMP/bundle" && find lib libexec -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
}
probe() {
  FIRE4NIX_BUNDLED_WPE_ROOT="$TMP/bundle" bash -c '
    APP_DIR="$1"
    source "$2"
    fire4nix_activate_bundled_wpe_runtime
    test "$FIRE4NIX_WPE_RUNTIME_ACTIVATED" = 1
    test "$WEBKIT_EXEC_PATH" = "$FIRE4NIX_BUNDLED_WPE_ROOT/libexec/wpe-webkit-2.0"
    case "$LD_LIBRARY_PATH" in "$FIRE4NIX_BUNDLED_WPE_ROOT/lib"*) ;; *) exit 1;; esac
  ' bash "$TMP/app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh"
}
reject() {
  local reason="$1"
  if probe > "$TMP/rejected.log" 2>&1; then
    echo "FAIL: accepted invalid bundled runtime ($reason)" >&2
    exit 1
  fi
}
write_manifest
probe > "$TMP/valid.log" 2>&1
grep -q 'checksum-verified WPE runtime activated' "$TMP/valid.log"
# Physical R36H logs use runtime/lib, not runtime/aarch64/lib.
ln -s "$TMP/bundle" "$TMP/app/runtime"
env -u FIRE4NIX_BUNDLED_WPE_ROOT FIRE4NIX_HOME="$TMP/app" bash -c '
    APP_DIR="$1"
    source "$2"
    fire4nix_activate_bundled_wpe_runtime
    test "$FIRE4NIX_WPE_RUNTIME_ACTIVATED" = 1
    test "$WEBKIT_EXEC_PATH" = "$3/libexec/wpe-webkit-2.0"
' bash "$TMP/app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh" "$TMP/bundle" > "$TMP/legacy.log" 2>&1
grep -q 'detected ROCKNIX legacy WPE layout:' "$TMP/legacy.log"
grep -q 'checksum-verified WPE runtime activated:' "$TMP/legacy.log"
# The production core ZIP uses a Python-generated checksum manifest rather
# than GNU sha256sum output. Both must pass the same safe path validation.
python3 - "$TMP/bundle" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
items = sorted(p for folder in ("lib", "libexec") for p in (root / folder).rglob("*") if p.is_file())
(root / "SHA256SUMS").write_text(
    "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}\n" for p in items)
)
PY
probe > "$TMP/python-manifest.log" 2>&1
grep -q 'checksum-verified WPE runtime activated' "$TMP/python-manifest.log"

# A known too-old device libc must be rejected *before* LD_LIBRARY_PATH is
# activated; newer versions must not be erroneously rejected.
mkdir -p "$TMP/mock-bin"
cat > "$TMP/mock-bin/getconf" <<'GETCONF'
#!/bin/sh
if [ "${1:-}" = GNU_LIBC_VERSION ]; then
  printf 'glibc %s\n' "${MOCK_GLIBC_VERSION:-2.0}"
else
  exit 1
fi
GETCONF
chmod +x "$TMP/mock-bin/getconf"
printf '%s\n' '{"highest_required_glibc_across_components":"GLIBC_2.38"}' > "$TMP/WPE-ABI-REQUIREMENTS.json"
PATH="$TMP/mock-bin:$PATH" MOCK_GLIBC_VERSION=2.0 reject 'host glibc older than WPE core ABI'
grep -q 'portable WPE requires GLIBC_2.38' "$TMP/rejected.log"
PATH="$TMP/mock-bin:$PATH" MOCK_GLIBC_VERSION=2.44 probe > "$TMP/compatible-glibc.log" 2>&1
grep -q 'checksum-verified WPE runtime activated' "$TMP/compatible-glibc.log"
# C++ runtime symbol floors must be evaluated independently of GLIBC.
# Mock readelf's version output so ARM64/x86_64 runners exercise the same
# boundary, without installing any foreign libstdc++ on the system.
cat > "$TMP/mock-bin/readelf" <<'READELF'
#!/bin/sh
if [ "${1:-}" = "--version-info" ]; then
  if [ "${MOCK_CPP_ABI_MODERN:-0}" = 1 ]; then
    printf '%s\n' 'Name: GLIBCXX_3.4.32' 'Name: CXXABI_1.3.14'
  else
    printf '%s\n' 'Name: GLIBCXX_3.4.29' 'Name: CXXABI_1.3.12'
  fi
else
  exec /usr/bin/readelf "$@"
fi
READELF
chmod +x "$TMP/mock-bin/readelf"
cat > "$TMP/WPE-ABI-REQUIREMENTS.json" <<'JSON'
{
  "highest_required_glibc_across_components": "GLIBC_2.38",
  "highest_required_cpp_abi_across_components": {
    "CXXABI": "CXXABI_1.3.13",
    "GLIBCXX": "GLIBCXX_3.4.30"
  }
}
JSON
PATH="$TMP/mock-bin:$PATH" MOCK_GLIBC_VERSION=2.44 reject 'libstdc++ GLIBCXX symbols too old'
grep -q 'requires GLIBCXX_3.4.30' "$TMP/rejected.log"
PATH="$TMP/mock-bin:$PATH" MOCK_GLIBC_VERSION=2.44 MOCK_CPP_ABI_MODERN=1 probe > "$TMP/compatible-cpp.log" 2>&1
grep -q 'checksum-verified WPE runtime activated' "$TMP/compatible-cpp.log"
# A newer GLIBCXX alone does not imply the CXXABI version is sufficient.
sed -i 's/CXXABI_1.3.13/CXXABI_1.3.15/g' "$TMP/WPE-ABI-REQUIREMENTS.json"
PATH="$TMP/mock-bin:$PATH" MOCK_GLIBC_VERSION=2.44 MOCK_CPP_ABI_MODERN=1 reject 'CXXABI symbols too old'
grep -q 'requires CXXABI_1.3.15' "$TMP/rejected.log"
rm -f "$TMP/WPE-ABI-REQUIREMENTS.json"

# All three helper executables are mandatory.
mv "$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" "$TMP/missing-gpu"
reject 'missing WPEGPUProcess'
mv "$TMP/missing-gpu" "$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess"

# A valid ELF magic without the correct target architecture is not accepted.
printf '\076\000' | dd of="$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" bs=1 seek=18 conv=notrunc 2>/dev/null
reject 'x86_64 ELF masquerading as AArch64'
printf '\267\000' | dd of="$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" bs=1 seek=18 conv=notrunc 2>/dev/null

# The checksum list must cover all required helper executables.
cp "$TMP/bundle/SHA256SUMS" "$TMP/complete-manifest"
grep -v 'WPENetworkProcess' "$TMP/complete-manifest" > "$TMP/bundle/SHA256SUMS"
reject 'checksum manifest missing WPENetworkProcess'
cp "$TMP/complete-manifest" "$TMP/bundle/SHA256SUMS"

# Foreign architecture dependencies cannot be mixed into the bundle.
cp /bin/true "$TMP/bundle/lib/libforeign.so.1"
printf '\076\000' | dd of="$TMP/bundle/lib/libforeign.so.1" bs=1 seek=18 conv=notrunc 2>/dev/null
reject 'foreign ELF shared library'
rm "$TMP/bundle/lib/libforeign.so.1"

# Preserve ROCKNIX's own libc and dynamic loader.
cp "$TMP/bundle/lib/libWPEWebKit-2.0.so" "$TMP/bundle/lib/libc.so.6"
reject 'bundled libc.so.6'
rm "$TMP/bundle/lib/libc.so.6"

# Symlinks may be used inside bundles, never to escape into system files.
ln -s /etc/passwd "$TMP/bundle/lib/malicious.so"
reject 'external runtime symlink'
rm "$TMP/bundle/lib/malicious.so"

# Explicitly reject checksum path traversal before sha256sum reads it.
printf '%064d  ../../etc/passwd\n' 0 >> "$TMP/bundle/SHA256SUMS"
reject 'checksum manifest traversal'
write_manifest
# Reject explicit './' components in manifest paths even with valid hashes.
sed 's@  lib/libWPEWebKit@  lib/./libWPEWebKit@' "$TMP/bundle/SHA256SUMS" > "$TMP/malformed-dot"
cp "$TMP/malformed-dot" "$TMP/bundle/SHA256SUMS"
reject 'checksum manifest dot segment'
write_manifest

# Bit flips must fail integrity verification.
printf X >> "$TMP/bundle/lib/libWPEWebKit-2.0.so"
reject 'checksum mismatch'
printf '%s\n' 'PASS: WPE runtime activation, verified legacy layout, GLIBC/GLIBCXX/CXXABI, checksums, symlinks and libc checks'
