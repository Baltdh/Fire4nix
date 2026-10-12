#!/bin/bash
set -u

# Fire4Nix WPE startup validation
# Validates launcher path resolution, certificate chains, Wayland/Sway detection,
# and dynamic module loading without executing the binary on host.
# Device-specific rendering, button input and network access remain untested.
#
# Exit codes:
#  0 = all checks passed
#  1 = critical failures found (blocks launch)
#  2 = environment issue (missing tools, cannot write report)

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$APP_DIR/scripts/fire4nix_env.sh" 2>/dev/null || true

fire4nix_bootstrap_environment "$APP_DIR" 2>/dev/null || true
fire4nix_export_wpe_common_env 2>/dev/null || true
fire4nix_wpe_runtime_env 2>/dev/null || true

CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root "$APP_DIR" 2>/dev/null || echo "$APP_DIR/.fire4nix")}"
LOG_DIR="$CONFIG_DIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true

STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo current)"
REPORT="${FIRE4NIX_STARTUP_REPORT:-$LOG_DIR/wpe-startup-validation-$STAMP.log}"

failures=0
warnings=0

say() {
    printf '%s\n' "$*" | tee -a "$REPORT" 2>/dev/null || printf '%s\n' "$*"
}

pass() {
    say "✓ $*"
}

warn() {
    warnings=$((warnings + 1))
    say "⚠ $*"
}

fail() {
    failures=$((failures + 1))
    say "✗ $*"
}

: > "$REPORT" 2>/dev/null || {
    printf 'Fire4Nix startup validation: cannot write report %s\n' "$REPORT" >&2
    exit 2
}

say "=== Fire4Nix WPE Startup Validation ==="
say "timestamp=$(date -Iseconds 2>/dev/null || date 2>/dev/null || echo unknown)"
say "app_dir=$APP_DIR"
say "report=$REPORT"
say ""

# ============================================================================
# 1. Launcher path and ARM64 ELF verification
# ============================================================================
say "=== Launcher Path Resolution ==="

native_binary="$(fire4nix_wpe_platform_binary 2>/dev/null || true)"
if [ -z "$native_binary" ]; then
    fail "fire4nix-wpe-platform binary not located"
    say "checked candidates:"
    say "  \${FIRE4NIX_WPE_PLATFORM_BINARY}"
    say "  \${FIRE4NIX_HOME:-\$APP_DIR}/bin/wpe-platform-launcher"
    say "  \${FIRE4NIX_HOME:-\$APP_DIR}/bin/wpe-platform"
    say "  \${FIRE4NIX_HOME:-\$APP_DIR}/build/fire4nix-wpe-platform"
    say "  \${FIRE4NIX_HOME:-\$APP_DIR}/build/wpe-platform"
    say "  \${FIRE4NIX_HOME:-\$APP_DIR}/bin/fire4nix-wpe-platform"
else
    say "binary=$native_binary"
    
    if [ ! -f "$native_binary" ]; then
        fail "binary file does not exist"
    elif [ ! -r "$native_binary" ]; then
        fail "binary file is not readable"
    else
        pass "binary file is readable"
    fi
    
    if command -v file >/dev/null 2>&1; then
        desc="$(file -b "$native_binary" 2>/dev/null || true)"
        say "file_type=$desc"
        if printf '%s' "$desc" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'; then
            pass "launcher is ARM64 ELF"
        else
            fail "launcher is not ARM64 ELF"
        fi
    else
        warn "file(1) not available; ARM64 ELF identity not verified"
    fi
    
    if [ -x "$native_binary" ]; then
        pass "launcher is executable"
    else
        warn "launcher is not executable (will need chmod +x post-extraction)"
    fi
fi

say ""
say "=== Launcher Dependency Resolution ==="

if [ -n "$native_binary" ] && command -v readelf >/dev/null 2>&1; then
    if readelf -d "$native_binary" 2>/dev/null | grep -q "NEEDED"; then
        needed=$(readelf -d "$native_binary" 2>/dev/null | grep NEEDED | wc -l)
        say "launcher_direct_dependencies=$needed"
        readelf -d "$native_binary" 2>/dev/null | grep NEEDED | sed 's/^/  /'
        
        # Check for dlopen indicators
        if readelf -s "$native_binary" 2>/dev/null | grep -q "dlopen\|dlsym"; then
            warn "launcher may use dlopen() for dynamic module loading (requires runtime validation)"
        fi
    else
        say "launcher_direct_dependencies=0"
    fi
elif [ -n "$native_binary" ]; then
    warn "readelf not available; dependency analysis skipped"
fi

say ""
say "=== Runtime Library Layout ==="

bundled_root="${FIRE4NIX_BUNDLED_WPE_ROOT:-$APP_DIR/runtime/aarch64}"
if [ -d "$bundled_root" ]; then
    pass "bundled runtime directory exists: $bundled_root"
    
    if [ -d "$bundled_root/lib" ]; then
        lib_count=$(find "$bundled_root/lib" -type f -name "*.so*" 2>/dev/null | wc -l)
        say "bundled_libraries=$lib_count"
        pass "bundled lib directory present"
    else
        warn "bundled lib directory not found"
    fi
    
    if [ -d "$bundled_root/libexec/wpe-webkit-2.0" ]; then
        pass "bundled libexec/wpe-webkit-2.0 present"
        for proc in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
            if [ -f "$bundled_root/libexec/wpe-webkit-2.0/$proc" ]; then
                pass "  $proc present"
            else
                fail "  $proc missing"
            fi
        done
    else
        fail "bundled libexec/wpe-webkit-2.0 directory not found"
    fi
else
    fail "bundled runtime directory not found: $bundled_root"
fi

say ""
say "=== Certificate and TLS Configuration ==="

# Check for system CA bundle paths
ca_paths=()
for ca_dir in /etc/ssl/certs /etc/pki/tls/certs /usr/local/share/ca-certificates; do
    [ -d "$ca_dir" ] && ca_paths+=("$ca_dir")
done

if [ ${#ca_paths[@]} -gt 0 ]; then
    pass "system CA certificate directories found:"
    for ca_dir in "${ca_paths[@]}"; do
        cert_count=$(find "$ca_dir" -type f \( -name "*.crt" -o -name "*.pem" \) 2>/dev/null | wc -l)
        say "  $ca_dir ($cert_count files)"
    done
else
    warn "no standard system CA certificate directories found (TLS may fail)"
fi

# Check for GIO TLS modules
gio_libs=""
if command -v pkg-config >/dev/null 2>&1; then
    gio_libs=$(pkg-config --variable=gio_modules gio-2.0 2>/dev/null || true)
fi
if [ -n "$gio_libs" ]; then
    say "gio_tls_modules=$gio_libs"
    for module_dir in $gio_libs; do
        if [ -d "$module_dir" ]; then
            tls_modules=$(find "$module_dir" -name "*tls*" -type f 2>/dev/null | wc -l)
            if [ "$tls_modules" -gt 0 ]; then
                pass "GIO TLS modules found in $module_dir ($tls_modules)"
            else
                warn "no GIO TLS modules in $module_dir"
            fi
        fi
    done
else
    warn "GIO TLS module path not available; pkg-config not found or gio-2.0 not installed"
fi

say ""
say "=== Wayland/Sway Platform Detection ==="

# Check environment variables
say "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
say "WAYLAND_SOCKET=${WAYLAND_SOCKET:-unset}"
say "DISPLAY=${DISPLAY:-unset}"
say "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
say "WPE_PLATFORM=${WPE_PLATFORM:-unset}"
say "WPE_DISPLAY=${WPE_DISPLAY:-unset}"

# Check Wayland socket availability
if fire4nix_wayland_socket_available 2>/dev/null; then
    socket_path=$(fire4nix_wayland_socket_path 2>/dev/null || true)
    say "wayland_socket=$socket_path"
    pass "Wayland socket is available"
else
    warn "Wayland socket not available; falling back to alternative display"
fi

# Check for Sway detection
if command -v swaymsg >/dev/null 2>&1; then
    pass "Sway is installed"
    if swaymsg --version 2>/dev/null | grep -q "sway"; then
        sway_version=$(swaymsg --version 2>/dev/null | head -1)
        say "sway_version=$sway_version"
    fi
else
    warn "swaymsg not in PATH; Sway window manager not detected"
fi

# Check for required libraries (optional, warn only)
wpe_needed_libs=(
    "libwayland-client.so"
    "libwayland-egl.so"
    "libEGL.so"
    "libGLESv2.so"
    "libxkbcommon.so"
)

say ""
say "=== Critical WPE Libraries ==="
for lib in "${wpe_needed_libs[@]}"; do
    found=0
    for search_dir in /usr/lib /usr/lib64 /usr/lib/aarch64-linux-gnu /lib /lib64 ${bundled_root}/lib; do
        if [ -d "$search_dir" ] && find "$search_dir" -name "$lib*" -type f 2>/dev/null | grep -q .; then
            found=1
            break
        fi
    done
    if [ "$found" -eq 1 ]; then
        pass "$lib available"
    else
        warn "$lib not found (Wayland may fail)"
    fi
done

say ""
say "=== Media Plugins and GStreamer ==="

# Check for GStreamer plugin paths
if command -v pkg-config >/dev/null 2>&1; then
    gst_plugin_path=$(pkg-config --variable=plugindir gstreamer-1.0 2>/dev/null || true)
    if [ -n "$gst_plugin_path" ]; then
        say "gstreamer_plugin_path=$gst_plugin_path"
        plugin_count=$(find "$gst_plugin_path" -name "*.so" -type f 2>/dev/null | wc -l)
        say "gstreamer_plugins=$plugin_count"
        if [ "$plugin_count" -gt 0 ]; then
            pass "GStreamer plugins available"
        else
            warn "GStreamer plugin directory exists but is empty"
        fi
    else
        warn "GStreamer plugin path not available"
    fi
else
    warn "pkg-config not available; GStreamer plugins not verified"
fi

say ""
say "=== Pre-launch Checks Summary ==="
say "failures=$failures"
say "warnings=$warnings"

if [ "$failures" -ne 0 ]; then
    say ""
    say "=== VALIDATION FAILED ==="
    say "Critical failures must be resolved before launch:"
    say "  exit_code=1"
    exit 1
fi

if [ "$warnings" -gt 0 ]; then
    say ""
    say "=== WARNINGS PRESENT ==="
    say "Launch may succeed, but some features may be unavailable"
    say "  exit_code=0 (warnings do not block)"
fi

say ""
say "=== VALIDATION PASSED ==="
say "Launcher passed validation checks."
say "Device rendering, button input and network access require on-device testing."
say "  exit_code=0"
exit 0
