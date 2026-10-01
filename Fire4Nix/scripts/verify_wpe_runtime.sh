#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_ROOT="${1:-${FIRE4NIX_BUNDLED_WPE_ROOT:-$APP_DIR/runtime/aarch64}}"

failures=0
say() { printf '%s\n' "$*"; }
fail() { say "FAIL: $*"; failures=$((failures + 1)); }
pass() { say "PASS: $*"; }

[ -d "$RUNTIME_ROOT" ] || {
    say "FAIL: bundled WPE runtime not found: $RUNTIME_ROOT"
    exit 1
}

LIB_DIR="$RUNTIME_ROOT/lib"
PROC_DIR="$RUNTIME_ROOT/libexec/wpe-webkit-2.0"

command -v file >/dev/null 2>&1 || {
    say "FAIL: file(1) is required to validate the WPE runtime"
    exit 2
}

for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    path="$PROC_DIR/$process"
    if [ ! -f "$path" ]; then
        fail "missing $process"
        continue
    fi
    desc=$(file -b "$path" 2>/dev/null || true)
    if printf '%s' "$desc" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'; then
        pass "$process is ARM64 ELF"
    else
        fail "$process is not ARM64 ELF ($desc)"
    fi
done

wpe_lib=""
for candidate in "$LIB_DIR"/libWPEWebKit-2.0.so "$LIB_DIR"/libWPEWebKit-2.0.so.*; do
    if [ -f "$candidate" ]; then
        wpe_lib="$candidate"
        break
    fi
done

if [ -z "$wpe_lib" ]; then
    fail "missing libWPEWebKit-2.0.so runtime library"
else
    desc=$(file -b "$wpe_lib" 2>/dev/null || true)
    if printf '%s' "$desc" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'; then
        pass "WPE WebKit runtime library is ARM64 ELF"
    else
        fail "WPE WebKit runtime library is not ARM64 ELF ($desc)"
    fi
fi

[ -f "$RUNTIME_ROOT/runtime.manifest" ] &&
    pass "runtime manifest present" ||
    fail "runtime.manifest is missing"

if [ "$failures" -ne 0 ]; then
    say "Fire4Nix bundled runtime validation failed: $failures issue(s)"
    exit 1
fi

say "Fire4Nix bundled WPE runtime validation passed"
