#!/bin/bash
set -u

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$APP_DIR/scripts/fire4nix_env.sh"

fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_export_wpe_common_env
fire4nix_wpe_runtime_env

CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root "$APP_DIR")}"
LOG_DIR="$CONFIG_DIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo current)"
REPORT="${FIRE4NIX_SMOKE_REPORT:-$LOG_DIR/rocknix-wpe-smoke-$STAMP.log}"

failures=0
warnings=0

say() {
    printf '%s\n' "$*" | tee -a "$REPORT"
}

pass() {
    say "PASS: $*"
}

warn() {
    warnings=$((warnings + 1))
    say "WARN: $*"
}

fail() {
    failures=$((failures + 1))
    say "FAIL: $*"
}

: > "$REPORT" 2>/dev/null || {
    printf 'Fire4Nix smoke test: cannot write report %s\n' "$REPORT" >&2
    exit 2
}

say "Fire4Nix ROCKNIX/WPE smoke report"
say "timestamp=$(date -Iseconds 2>/dev/null || date 2>/dev/null || echo unknown)"
say "app_dir=$APP_DIR"
say "arch=$(uname -m 2>/dev/null || echo unknown)"
say "kernel=$(uname -r 2>/dev/null || echo unknown)"
say "wpe_platform=${WPE_PLATFORM:-unset}"
say "wpe_display_legacy=${WPE_DISPLAY:-unset}"
say "wayland_display=${WAYLAND_DISPLAY:-unset}"
say "xdg_runtime_dir=${XDG_RUNTIME_DIR:-unset}"
say "target_size=${FIRE4NIX_DISPLAY_WIDTH:-640}x${FIRE4NIX_DISPLAY_HEIGHT:-480}"

case "$(uname -m 2>/dev/null || true)" in
    aarch64|arm64)
        pass "CPU userspace is ARM64"
        ;;
    *)
        fail "expected ARM64/aarch64 userspace for the R36H ROCKNIX target"
        ;;
esac

if [ "${WPE_PLATFORM:-}" = "wayland" ] || [ "${WPE_DISPLAY:-}" = "wpe-display-wayland" ]; then
    if fire4nix_wayland_socket_available; then
        say "wayland_socket=$(fire4nix_wayland_socket_path)"
        pass "Wayland socket is available"
    else
        fail "WPE selected Wayland but the Wayland socket is not available"
    fi
else
    warn "WPE platform is ${WPE_PLATFORM:-unset}; Wayland is the preferred R36H path"
fi

native_binary="$(fire4nix_wpe_platform_binary)"
if [ -z "$native_binary" ]; then
    fail "native fire4nix-wpe-platform binary was not found"
else
    say "native_binary=$native_binary"
    if command -v file >/dev/null 2>&1; then
        desc="$(file -b "$native_binary" 2>/dev/null || true)"
        say "native_binary_file=$desc"
        if printf '%s' "$desc" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'; then
            pass "native launcher is an ARM64 ELF"
        else
            fail "native launcher is not an ARM64 ELF"
        fi
    else
        warn "file(1) is unavailable; ARM64 ELF identity was not independently verified"
    fi

    if [ -x "$native_binary" ]; then
        pass "native launcher is executable"
    else
        fail "native launcher is not executable"
    fi
fi

wpe_pkg=""
if command -v pkg-config >/dev/null 2>&1; then
    for pkg in wpe-webkit-2.0 wpe-webkit wpewebkit; do
        if pkg-config --exists "$pkg" >/dev/null 2>&1; then
            wpe_pkg="$pkg"
            break
        fi
    done
fi

if [ -n "$wpe_pkg" ]; then
    version="$(pkg-config --modversion "$wpe_pkg" 2>/dev/null || echo unknown)"
    say "wpe_package=$wpe_pkg"
    say "wpe_version=$version"
    if pkg-config --atleast-version=2.52.6 "$wpe_pkg" >/dev/null 2>&1; then
        pass "WPE WebKit meets the 2.52.6 security baseline"
    else
        fail "WPE WebKit is older than the 2.52.6 security baseline"
    fi
    if pkg-config --atleast-version=2.54.0 "$wpe_pkg" >/dev/null 2>&1; then
        warn "WPE 2.54+ uses the Skia web-process compositor; benchmark it on RK3326 before release"
    fi
else
    warn "pkg-config could not identify WPE WebKit; runtime libraries may still be present"
fi

if [ -r /proc/meminfo ]; then
    mem_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
    say "mem_total_kib=${mem_kib:-0}"
    if [ "${mem_kib:-0}" -gt 0 ] && [ "$mem_kib" -lt 700000 ]; then
        warn "available system memory is below the expected ~1 GB class target"
    fi
fi

if [ -d /dev/dri ]; then
    pass "/dev/dri is present"
else
    warn "/dev/dri is missing; accelerated WPE rendering may be unavailable"
fi

bundled_root="$(fire4nix_bundled_wpe_root)"
if [ -d "$bundled_root" ]; then
    if sh "$APP_DIR/scripts/verify_wpe_runtime.sh" "$bundled_root" >> "$REPORT" 2>&1; then
        pass "bundled WPE runtime passed integrity checks"
    else
        fail "bundled WPE runtime failed integrity checks"
    fi
else
    warn "bundled WPE runtime is not staged yet"
fi

if command -v bwrap >/dev/null 2>&1; then
    pass "Bubblewrap executable is available for the WebKit sandbox"
else
    warn "bwrap is not in PATH; verify WebKit sandbox behavior before release"
fi

say "failures=$failures"
say "warnings=$warnings"
say "report=$REPORT"

if [ "$failures" -ne 0 ]; then
    exit 1
fi
exit 0
