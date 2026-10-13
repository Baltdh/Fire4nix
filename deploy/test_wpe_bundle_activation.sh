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

# All three helper executables are mandatory.
mv "$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" "$TMP/missing-gpu"
reject 'missing WPEGPUProcess'
mv "$TMP/missing-gpu" "$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess"

# A valid ELF magic without the correct target architecture is not accepted.
printf '\076\000' | dd of="$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" bs=1 seek=18 conv=notrunc 2>/dev/null
reject 'x86_64 ELF masquerading as AArch64'
printf '\267\000' | dd of="$TMP/bundle/libexec/wpe-webkit-2.0/WPEGPUProcess" bs=1 seek=18 conv=notrunc 2>/dev/null

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

# Bit flips must fail integrity verification.
printf X >> "$TMP/bundle/lib/libWPEWebKit-2.0.so"
reject 'checksum mismatch'
printf '%s\n' 'PASS: optional WPE runtime activation, architecture, integrity, symlink and libc safety checks'
