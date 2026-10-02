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
    [ -x "$path" ] || fail "$process is not executable"
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

# Verify the checksums emitted by stage_wpe_runtime.sh, without accepting
# absolute paths or parent traversal from a malformed manifest.
if [ -f "$RUNTIME_ROOT/runtime.manifest" ]; then
    command -v sha256sum >/dev/null 2>&1 || {
        say "FAIL: sha256sum is required to validate runtime integrity"
        exit 2
    }
    CHECKSUMS=$(mktemp)
    trap 'rm -f "$CHECKSUMS"' EXIT HUP INT TERM
    if awk '
        /^\[sha256\]$/ { hashes=1; next }
        hashes && NF {
            hash=substr($0,1,64); path=substr($0,67);
            if (length(hash)!=64 || hash ~ /[^0-9a-f]/ ||
                substr($0,65,2)!="  " || path !~ /^(lib|libexec|share)\// ||
                path ~ /(^|\/)\.\.(\/|$)/ || path ~ /\\/) { bad=1; next }
            print; count++
        }
        END { if (bad || !count) exit 1 }
    ' "$RUNTIME_ROOT/runtime.manifest" > "$CHECKSUMS"; then
        for required in "libexec/wpe-webkit-2.0/WPEWebProcess" "libexec/wpe-webkit-2.0/WPENetworkProcess" "libexec/wpe-webkit-2.0/WPEGPUProcess"; do
            grep -Fq "  $required" "$CHECKSUMS" || fail "manifest does not cover $required"
        done
        if [ -n "$wpe_lib" ]; then
            resolved_lib=$(readlink -f "$wpe_lib" 2>/dev/null || printf '%s' "$wpe_lib")
            resolved_root=$(CDPATH= cd -- "$RUNTIME_ROOT" && pwd -P)
            case "$resolved_lib" in
                "$resolved_root"/lib/*) relative_lib="${resolved_lib#"$resolved_root"/}" ;;
                *) relative_lib=""; fail "WPE library resolves outside the bundled lib directory" ;;
            esac
            grep -Fq "  $relative_lib" "$CHECKSUMS" || fail "manifest does not cover WPE library"
        fi
        if (cd "$RUNTIME_ROOT" && sha256sum -c "$CHECKSUMS"); then
            pass "runtime SHA-256 integrity checks passed"
        else
            fail "runtime checksum mismatch or missing file"
        fi
    else
        fail "runtime checksum section is empty or malformed"
    fi
fi

if [ "$failures" -ne 0 ]; then
    say "Fire4Nix bundled runtime validation failed: $failures issue(s)"
    exit 1
fi

say "Fire4Nix bundled WPE runtime validation passed"
