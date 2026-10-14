#!/usr/bin/env bash
# The native WPE subprocess must not contaminate Cog with bundled libraries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "FAIL: WPE/Cog isolation test exit $status" >&2
    for log in "$TMP"/*.log; do
      if [ -f "$log" ]; then echo "--- $log ---" >&2; cat "$log" >&2; fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/runtime" "$TMP/safe"
cat > "$TMP/bin/mock-wpe" <<'WPE'
#!/usr/bin/env bash
printf 'WPE_STARTED=1\nWPE_LD=%s\nWPE_EXEC=%s\n' "${LD_LIBRARY_PATH:-unset}" "${WEBKIT_EXEC_PATH:-unset}"
exit "${MOCK_WPE_STATUS:-42}"
WPE
cat > "$TMP/bin/cog" <<'COG'
#!/usr/bin/env bash
printf 'COG_STARTED=1\n'
printf 'COG_LD=%s\n' "${LD_LIBRARY_PATH:-unset}"
printf 'COG_EXEC=%s\n' "${WEBKIT_EXEC_PATH:-unset}"
printf 'COG_GIO=%s\n' "${GIO_EXTRA_MODULES:-unset}"
printf 'COG_GST=%s\n' "${GST_PLUGIN_PATH:-unset}"
exit 0
COG
chmod +x "$TMP/bin/mock-wpe" "$TMP/bin/cog"

run_case() {
  env PATH="$TMP/bin:$PATH" \
      FIRE4NIX_WPE_PLATFORM_BINARY="$TMP/bin/mock-wpe" \
      FIRE4NIX_HOME="$TMP/home" FIRE4NIX_RUNTIME_DIR="$TMP/runtime" \
      FIRE4NIX_CONFIG_DIR="$TMP/runtime/config" \
      LD_LIBRARY_PATH="$TMP/safe" WEBKIT_EXEC_PATH=original-exec-path \
      GIO_EXTRA_MODULES=original-gio-path GST_PLUGIN_PATH=original-gst-path \
      "$@" bash -c '
        APP_DIR="$1"
        source "$2"
        fire4nix_activate_bundled_wpe_runtime() {
          export LD_LIBRARY_PATH=unsafe-wpe-lib
          export WEBKIT_EXEC_PATH=unsafe-wpe-exec
          export GIO_EXTRA_MODULES=unsafe-wpe-gio
          export GST_PLUGIN_PATH=unsafe-wpe-gst
          if [ "${MOCK_PREFLIGHT_FAIL:-0}" = 1 ]; then
            echo "PREFLIGHT_FAILED=1"
            return 1
          fi
          return 0
        }
        fire4nix_launch_wpe_platform "https://example.org/isolation"
      ' bash "$TMP/home" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh"
}
run_case MOCK_WPE_STATUS=42 > "$TMP/crash.log" 2>&1
grep -q '^WPE_STARTED=1$' "$TMP/crash.log"
grep -q '^WPE_LD=unsafe-wpe-lib$' "$TMP/crash.log"
grep -q '^WPE_EXEC=unsafe-wpe-exec$' "$TMP/crash.log"
grep -q '^COG_STARTED=1$' "$TMP/crash.log"
grep -Fqx "COG_LD=$TMP/safe" "$TMP/crash.log"
grep -Fqx 'COG_EXEC=original-exec-path' "$TMP/crash.log"
grep -Fqx 'COG_GIO=original-gio-path' "$TMP/crash.log"
grep -Fqx 'COG_GST=original-gst-path' "$TMP/crash.log"

run_case MOCK_PREFLIGHT_FAIL=1 > "$TMP/preflight.log" 2>&1
grep -q '^PREFLIGHT_FAILED=1$' "$TMP/preflight.log"
if grep -q '^WPE_STARTED=1$' "$TMP/preflight.log"; then
  echo 'FAIL: WPE started after preflight rejected runtime' >&2
  exit 1
fi
grep -q '^COG_STARTED=1$' "$TMP/preflight.log"
grep -Fqx "COG_LD=$TMP/safe" "$TMP/preflight.log"
grep -Fqx 'COG_EXEC=original-exec-path' "$TMP/preflight.log"
grep -Fqx 'COG_GIO=original-gio-path' "$TMP/preflight.log"
grep -Fqx 'COG_GST=original-gst-path' "$TMP/preflight.log"

run_case MOCK_WPE_STATUS=0 > "$TMP/success.log" 2>&1
grep -q '^WPE_STARTED=1$' "$TMP/success.log"
if grep -q '^COG_STARTED=1$' "$TMP/success.log"; then
  echo 'FAIL: successful WPE launched Cog' >&2
  exit 1
fi
echo 'PASS: WPE crash, failed bundle preflight, successful startup all isolate loader environment.'
