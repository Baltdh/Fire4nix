#!/usr/bin/env bash
# Validate the physical-device test with a mock WPE executable.
# The mock is NOT evidence of real hardware/sandbox qualification.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "DEVICE SMOKE MOCK REGRESSION FAILED ($status)" >&2
        find "$TMP" -type f \( -name RESULT.txt -o -name launcher.log -o -name '*.log' \) \
            -exec sh -c 'echo "--- $1 ---"; tail -70 "$1"' sh {} \; >&2 || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

cat > "$TMP/mock-wpe" <<'MOCK'
#!/usr/bin/env bash
printf 'MOCK_SANDBOX_OVERRIDE=%s\n' "${WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS:-unset}"
printf 'MOCK_PLATFORM=%s\n' "${WPE_PLATFORM:-unset}"
printf 'MOCK_ARGS=%s\n' "$*"
if [ "${FIRE4NIX_TEST_MOCK_FAIL:-0}" = 1 ]; then
    echo 'Fire4Nix WPE load failed'
    exit 12
fi
mkdir -p "$FIRE4NIX_RUNTIME_DIR"
printf 'event=load-finished\nloading=0\n' > "$FIRE4NIX_RUNTIME_DIR/browser.state"
printf 'Fire4Nix WPE finished: file://test\n'
MOCK
chmod +x "$TMP/mock-wpe"

run_fixture() {
    env \
        FIRE4NIX_APP_DIR="$ROOT/navegador-definitivo" \
        FIRE4NIX_DEVICE_TEST_REPORT_DIR="$TMP/reports" \
        FIRE4NIX_DEVICE_TEST_ALLOW_NON_ARM64=1 \
        FIRE4NIX_WPE_PLATFORM_BINARY="$TMP/mock-wpe" \
        WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
        "$@" \
        bash "$ROOT/deploy/Fire4Nix-WPE-Teste-Real.sh" --headless
}

run_fixture > "$TMP/pass.log"
grep -q 'PASS: WPE loaded local HTML with sandbox override unset' "$TMP/pass.log"
run_dir="$(find "$TMP/reports" -maxdepth 1 -type d -name 'test-headless.*' | head -1)"
test -n "$run_dir"
test "$(stat -c '%a' "$run_dir")" = 700
grep -q 'MOCK_SANDBOX_OVERRIDE=unset' "$run_dir/launcher.log"
grep -q 'MOCK_PLATFORM=headless' "$run_dir/launcher.log"
grep -q 'MOCK_ARGS=--headless --exit-after-load file://' "$run_dir/launcher.log"
test -f "$run_dir/final-browser.state"

if run_fixture FIRE4NIX_TEST_MOCK_FAIL=1 > "$TMP/fail.log"; then
    echo 'FAIL: failed WPE navigation was accepted' >&2
    exit 1
fi
grep -q 'FAIL: WPE did not verify local HTML load' "$TMP/fail.log"
if grep -q 'PASS: WPE loaded' "$TMP/fail.log"; then
    echo 'FAIL: WPE failure reported success' >&2
    exit 1
fi

if env -u WAYLAND_DISPLAY \
    FIRE4NIX_APP_DIR="$ROOT/navegador-definitivo" \
    FIRE4NIX_DEVICE_TEST_REPORT_DIR="$TMP/reports" \
    FIRE4NIX_DEVICE_TEST_ALLOW_NON_ARM64=1 \
    FIRE4NIX_WPE_PLATFORM_BINARY="$TMP/mock-wpe" \
    bash "$ROOT/deploy/Fire4Nix-WPE-Teste-Real.sh" --wayland > "$TMP/no-wayland.log"; then
    echo 'FAIL: missing Wayland socket was accepted' >&2
    exit 1
fi
grep -q 'SKIP: Wayland environment variables unavailable' "$TMP/no-wayland.log"
echo 'PASS: offline device smoke detects success/failure, strips unsafe flag and checks Wayland preconditions'
