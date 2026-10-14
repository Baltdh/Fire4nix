#!/usr/bin/env bash
# R36H: use WPE runtime files already on SD; never overwrite system libraries.
# An initial local checksum baseline does NOT authenticate downloaded content.
set -euo pipefail
umask 077
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP="${FIRE4NIX_APP_DIR:-}"
if [ -z "$APP" ]; then
  for path in "$HERE/Fire4Nix" "$HERE" /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix; do
    if [ -f "$path/scripts/fire4nix_env.sh" ]; then APP="$path"; break; fi
  done
fi
[ -n "$APP" ] || { echo 'ERROR: Fire4Nix folder not found'; exit 2; }
APP="$(cd "$APP" && pwd -P)"
ROOT="$APP/runtime"
[ ! -d "$ROOT/aarch64/lib" ] || ROOT="$ROOT/aarch64"
LIB="$ROOT/lib"
PROC="$ROOT/libexec/wpe-webkit-2.0"
REPORTDIR="${FIRE4NIX_REPAIR_REPORT_DIR:-/storage/fire4nix-device-tests}"
mkdir -p "$REPORTDIR" 2>/dev/null || REPORTDIR="${TMPDIR:-/tmp}/fire4nix-device-tests"
mkdir -p "$REPORTDIR"
chmod 700 "$REPORTDIR" 2>/dev/null || true
REPORT="$REPORTDIR/legacy-runtime-preparation.log"
exec > >(tee "$REPORT") 2>&1
echo "Fire4Nix R36H runtime preparation: $(date)"
echo "App: $APP"
echo "Runtime: $ROOT"
echo 'System changes: NONE; WebKit sandbox: UNCHANGED'
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: ARM64 required'; exit 2; }
[ -d "$LIB" ] && [ -d "$PROC" ] || { echo 'ERROR: incomplete runtime/lib or libexec'; exit 3; }
WPE=""
for path in "$LIB"/libWPEWebKit-2.0.so.1 "$LIB"/libWPEWebKit-2.0.so "$LIB"/libWPEWebKit-2.0.so.*; do
  if [ -f "$path" ]; then WPE="$path"; break; fi
done
[ -n "$WPE" ] || { echo 'ERROR: missing bundled libWPEWebKit-2.0.so.1'; exit 3; }
for path in "$LIB"/libc.so* "$LIB"/ld-linux* "$LIB"/ld-*.so*; do
  if [ -e "$path" ] || [ -L "$path" ]; then
    echo "ERROR: bundled system loader/libc forbidden: $path"
    exit 4
  fi
done
for command in od sha256sum readlink find sort xargs; do
  command -v "$command" >/dev/null || { echo "ERROR: missing $command"; exit 4; }
done
while IFS= read -r -d '' link; do
  real="$(readlink -f "$link")" || exit 4
  case "$real" in "$ROOT"/*) ;; *) echo "ERROR: external symlink: $link"; exit 4 ;; esac
done < <(find "$ROOT" -type l -print0)
for path in "$WPE" "$PROC/WPEWebProcess" "$PROC/WPENetworkProcess" "$PROC/WPEGPUProcess"; do
  [ -f "$path" ] && [ -x "$path" ] || { echo "ERROR: missing/non-executable: $path"; exit 5; }
  head="$(od -An -tx1 -N6 "$path" | tr -d '[:space:]')"
  machine="$(od -An -tx1 -j18 -N2 "$path" | tr -d '[:space:]')"
  [ "$head" = 7f454c460201 ] && [ "$machine" = b700 ] || {
    echo "ERROR: non-AArch64 ELF: $path"
    exit 5
  }
done
echo 'PASS: core library and three WPE helper executables are ELF64 AArch64'
if [ -f "$ROOT/SHA256SUMS" ]; then
  echo 'Existing integrity manifest: checking without overwrite'
else
  [ -w "$ROOT" ] || { echo 'ERROR: runtime directory not writable'; exit 6; }
  echo 'Creating first-use SHA256 baseline (NOT source authentication)...'
  TMP="$ROOT/.SHA256SUMS.$$.tmp"
  trap 'rm -f "$TMP"' EXIT
  (cd "$ROOT"; for folder in lib libexec share; do
     [ ! -d "$folder" ] || find "$folder" -type f -print0
   done | LC_ALL=C sort -z | xargs -0 -r sha256sum) > "$TMP"
  [ -s "$TMP" ] || { echo 'ERROR: empty SHA256 manifest'; exit 6; }
  chmod 600 "$TMP"
  mv "$TMP" "$ROOT/SHA256SUMS"
  trap - EXIT
fi
(cd "$ROOT"; sha256sum -c SHA256SUMS >/dev/null) || {
  echo 'ERROR: checksum mismatch; refusing runtime activation'
  exit 6
}
echo 'PASS: SHA256SUMS validated'
export LD_LIBRARY_PATH="$LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$PROC"
echo "LD_LIBRARY_PATH begins with $LIB"
echo "WEBKIT_EXEC_PATH=$PROC"
NATIVE="$APP/bin/fire4nix-wpe-platform"
missing=0
if [ -f "$NATIVE" ] && command -v ldd >/dev/null 2>&1; then
  for target in "$NATIVE" "$WPE" "$PROC/WPEWebProcess" "$PROC/WPENetworkProcess" "$PROC/WPEGPUProcess"; do
    echo "Checking dynamic dependencies: $target"
    status=0
    if command -v timeout >/dev/null 2>&1; then
      result="$(timeout 40s ldd "$target" 2>&1)" || status=$?
    else
      result="$(ldd "$target" 2>&1)" || status=$?
    fi
    errors="$(printf '%s\n' "$result" | grep -E 'not found|version .* not found|error while loading' || true)"
    if [ "$status" -ne 0 ]; then
      echo "WARNING: ldd returned $status for $target (not verified)"
      printf '%s\n' "$result" | tail -12
      missing=1
    fi
    if [ -n "$errors" ]; then
      printf '%s\n' "$errors"
      missing=1
    fi
  done
fi
if [ "$missing" -ne 0 ]; then
  echo 'BLOCKED: WPE has additional missing dependencies.'
  echo 'Preserve this report; do not replace ROCKNIX system libraries.'
  exit 8
fi
echo 'PASS: no missing libraries reported by ldd.'
echo 'Next: use updated Fire4Nix scripts and test Wayland; sandbox stays enabled.'
echo "Saved report: $REPORT"
