#!/bin/sh
# A purely local test: no WPE, GPU, SD card or user data involved.
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/sandbox with space/Fire4Nix/bin" \
    "$T/sandbox with space/Fire4Nix/runtime/lib" "$T/sandbox with space/Fire4Nix/runtime/libexec/wpe-webkit-2.0" "$T/logs"
cp "$BASE/installer/Fire4Nix-Direto.sh" "$T/sandbox with space/Fire4Nix-Direto.sh"
printf 'fake-binary' > "$T/sandbox with space/Fire4Nix/bin/fire4nix-native-aarch64"
printf 'fake-runtime' > "$T/sandbox with space/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1"
for child in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'fake-child' > "$T/sandbox with space/Fire4Nix/runtime/libexec/wpe-webkit-2.0/$child"
done
cat > "$T/sandbox with space/Fire4Nix/Fire4Nix-Iniciar.sh" <<'FAKE'
#!/bin/sh
printf 'mock_browser_start args=%s\n' "$*" >&2
exit "${MOCK_EXIT:-0}"
FAKE
LAUNCH="$T/sandbox with space/Fire4Nix-Direto.sh"
ROOT="$T/sandbox with space/Fire4Nix"
(
  cd /
  FIRE4NIX_ROOT="$ROOT" FIRE4NIX_LOG_DIR="$T/logs" \
  sh "$LAUNCH" >/dev/null
)
grep -q '^real_browser_exit=0$' "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
grep -q '^mock_browser_start args=--open' "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
set +e
(
  cd /tmp
  MOCK_EXIT=139 FIRE4NIX_ROOT="$ROOT" FIRE4NIX_LOG_DIR="$T/logs" \
  sh "$LAUNCH" >/dev/null
)
status=$?
set -e
test "$status" -eq 139
grep -q '^real_browser_exit=139$' "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
grep -q '^diagnosis=SIGSEGV_' "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
# An incomplete first candidate must not mask a complete browser alongside it.
mkdir -p "$T/sandbox with space/fire4nix-completo/bin" "$T/sandbox with space/fire4nix-completo/runtime/lib"
cp "$ROOT/Fire4Nix-Iniciar.sh" "$T/sandbox with space/fire4nix-completo/Fire4Nix-Iniciar.sh"
cp "$ROOT/bin/fire4nix-native-aarch64" "$T/sandbox with space/fire4nix-completo/bin/"
cp "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1" "$T/sandbox with space/fire4nix-completo/runtime/lib/"
(
  cd /
  FIRE4NIX_LOG_DIR="$T/logs" sh "$LAUNCH" >/dev/null
)
grep -q "^skipped_incomplete_runtime=.*fire4nix-completo missing=" "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
grep -q "^selected_install=$ROOT$" "$T/sandbox with space/Fire4Nix-PORTS-ultimo.txt"
# A corrupt/empty package must NOT be advertised as a successful launch.
set +e
FIRE4NIX_ROOT="$T/empty" sh "$BASE/installer/Fire4Nix-Direto.sh" >/dev/null
status=$?
set -e
test "$status" -eq 127
# This branch also addresses two confirmed launch mistakes in the legacy scripts.
! grep -q '^exec fire4nix_launch_engine ' "$BASE/source_r36h/Fire4Nix/scripts/wpe_platform_launch.sh"
grep -q 'Never shadow the active ROCKNIX compositor socket' "$BASE/source_r36h/Fire4Nix/scripts/run_browser.sh"
sh -n "$BASE/installer/Fire4Nix-Direto.sh"
bash -n "$BASE/source_r36h/Fire4Nix/scripts/run_browser.sh"
bash -n "$BASE/source_r36h/Fire4Nix/scripts/wpe_platform_launch.sh"
printf 'PASS: Ports from any cwd, spaces in paths, native error 139 preserved, missing-package refusal\n'
