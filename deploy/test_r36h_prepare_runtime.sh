#!/usr/bin/env bash
# Validate one-time R36H repair script with tiny ARM64-header fixtures only.
# Neither the WPE library nor its subprocesses are ever executed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Tools/Fire4Nix"
mkdir -p "$APP/runtime/libexec/wpe-webkit-2.0" "$APP/runtime/lib" "$APP/scripts" "$APP/bin" "$TMP/mock-bin" "$TMP/logs"
printf '#!/bin/sh\n' > "$APP/scripts/fire4nix_env.sh"
for file in "$APP/bin/fire4nix-wpe-platform" "$APP/runtime/lib/libWPEWebKit-2.0.so.1" \
  "$APP/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" \
  "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" \
  "$APP/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"; do
  cp /bin/true "$file"
  printf '\267\000' | dd of="$file" bs=1 seek=18 conv=notrunc 2>/dev/null
  chmod +x "$file"
done
cat > "$TMP/mock-bin/uname" <<'SH'
#!/bin/sh
if [ "${1:-}" = '-m' ]; then printf 'aarch64\n'; else /usr/bin/uname "$@"; fi
SH
cat > "$TMP/mock-bin/ldd" <<'SH'
#!/bin/sh
if [ "${MOCK_MISSING:-0}" = 1 ]; then
  echo 'libSoup3.so.0 => not found'
else
  echo 'libc.so.6 => /usr/lib/libc.so.6'
fi
SH
chmod +x "$TMP/mock-bin/uname" "$TMP/mock-bin/ldd"
run() {
  FIRE4NIX_APP_DIR="$APP" FIRE4NIX_REPAIR_REPORT_DIR="$TMP/logs" \
    PATH="$TMP/mock-bin:$PATH" bash "$ROOT/deploy/Fire4Nix-Preparar-Runtime-R36H.sh"
}
run > "$TMP/success.log" 2>&1
grep -q 'PASS: no missing libraries reported by ldd.' "$TMP/success.log"
test -s "$APP/runtime/SHA256SUMS"
( cd "$APP/runtime" && sha256sum -c SHA256SUMS >/dev/null )
cp "$APP/runtime/SHA256SUMS" "$TMP/original-checksums"
run > "$TMP/repeated.log" 2>&1
cmp "$TMP/original-checksums" "$APP/runtime/SHA256SUMS"
if MOCK_MISSING=1 run > "$TMP/missing.log" 2>&1; then
  echo 'FAIL: missing transitive dependency was accepted' >&2
  exit 1
fi
grep -q 'libSoup3.so.0 => not found' "$TMP/missing.log"
printf X >> "$APP/runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
if run > "$TMP/tamper.log" 2>&1; then
  echo 'FAIL: modified WebProcess accepted after SHA256 baseline' >&2
  exit 1
fi
grep -q 'checksum mismatch' "$TMP/tamper.log"
printf '%s\n' 'PASS: R36H legacy runtime preparation, baseline reuse, missing deps and tampering rejection'
