#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

fail() {
    printf 'Fire4Nix One File: ERROR: %s\n' "$*" >&2
    exit 2
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required to build the ZIP"
command -v file >/dev/null 2>&1 || fail "file(1) is required to verify the ARM64 launcher"

NATIVE="$ROOT_DIR/bin/fire4nix-wpe-platform"
[ -f "$NATIVE" ] || fail "missing bin/fire4nix-wpe-platform; build the native WPE launcher first"

DESC=$(file -b "$NATIVE" 2>/dev/null || true)
printf '%s' "$DESC" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)' ||
    fail "bin/fire4nix-wpe-platform is not an ARM64 ELF ($DESC)"

RUNTIME_ROOT="$ROOT_DIR/runtime/aarch64"
[ -x "$ROOT_DIR/scripts/verify_wpe_runtime.sh" ] ||
    chmod +x "$ROOT_DIR/scripts/verify_wpe_runtime.sh" 2>/dev/null || true
sh "$ROOT_DIR/scripts/verify_wpe_runtime.sh" "$RUNTIME_ROOT" ||
    fail "bundled WPE runtime is incomplete; One File must be self-contained on ROCKNIX"

# Structural runtime checks do not establish dependency closure. Audit the
# library, subprocesses and native launcher without executing ARM64 code.
command -v readelf >/dev/null 2>&1 || fail "readelf is required for dependency verification"
DEPENDENCY_REPORT=$(mktemp)
trap 'rm -f "$DEPENDENCY_REPORT"' EXIT HUP INT TERM
set -- "$RUNTIME_ROOT" --launcher "$NATIVE"
if [ -n "${ROCKNIX_SYSROOT:-}" ]; then
    set -- "$@" --sysroot "$ROCKNIX_SYSROOT"
fi
if ! python3 "$ROOT_DIR/scripts/audit_runtime_dependencies.py" "$@" > "$DEPENDENCY_REPORT"; then
    cat "$DEPENDENCY_REPORT" >&2
    fail "unresolved ARM64 dependencies or incompatible version requirements; bundle them or supply the target ROCKNIX_SYSROOT"
fi
export FIRE4NIX_DEPENDENCY_REPORT="$DEPENDENCY_REPORT"

VERSION=$(sed -n '1s/^Fire4Nix[[:space:]]*//p' VERSION 2>/dev/null | tr -c '[:alnum:]._-\n' '-' | tr -d '\n')
[ -n "$VERSION" ] || VERSION="dev"
OUT_DIR="${FIRE4NIX_DIST_DIR:-$ROOT_DIR/dist}"
OUT="${FIRE4NIX_ONE_FILE_OUTPUT:-$OUT_DIR/Fire4Nix-OneFile-$VERSION.zip}"
mkdir -p "$OUT_DIR"
rm -f "$OUT" "$OUT.sha256"

export FIRE4NIX_PACKAGE_ROOT="$ROOT_DIR"
export FIRE4NIX_PACKAGE_OUTPUT="$OUT"

python3 <<'PY'
import hashlib
import os
import stat
import zipfile
from pathlib import Path

root = Path(os.environ["FIRE4NIX_PACKAGE_ROOT"]).resolve()
output = Path(os.environ["FIRE4NIX_PACKAGE_OUTPUT"]).resolve()

required = [
    "Fire4Nix.sh",
    "VERSION",
    "fire4nix.conf",
    "firefox-framebuffer-wrapper.py",
    "bin/browser.arm64",
    "bin/fire4nix-wpe-platform",
    "scripts/fire4nix_env.sh",
    "scripts/run_browser.sh",
    "scripts/wpe_platform_launch.sh",
    "scripts/wpe_cog_launch.sh",
    "scripts/browser_manager.sh",
    "scripts/engine_manager.sh",
    "scripts/theme_manager.sh",
    "scripts/rocknix_wpe_smoke_test.sh",
    "scripts/verify_wpe_runtime.sh",
    "scripts/validate_wpe_startup.sh",
]

for rel in required:
    path = root / rel
    if not path.is_file():
        raise SystemExit(f"missing runtime file: {rel}")

optional_trees = [
    root / ".mozilla_profile",
    root / "theme",
    root / "runtime",
]

root_launcher = """#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$HERE/Fire4Nix"
[ -d "$APP" ] || {
    echo "Fire4Nix folder not found next to launcher." >&2
    exit 1
}
exec sh "$APP/Fire4Nix.sh" "$@"
"""

diagnostic_launcher = """#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$HERE/Fire4Nix"
REPORT="$HERE/Fire4Nix-test-report.log"
[ -f "$APP/scripts/rocknix_wpe_smoke_test.sh" ] || {
    echo "Fire4Nix diagnostic script not found." >&2
    exit 1
}
export FIRE4NIX_SMOKE_REPORT="$REPORT"
exec bash "$APP/scripts/rocknix_wpe_smoke_test.sh"
"""

startup_validator = """#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$HERE/Fire4Nix"
REPORT="$HERE/Fire4Nix-startup-validation.log"
[ -f "$APP/scripts/validate_wpe_startup.sh" ] || {
    echo "Fire4Nix startup validation script not found." >&2
    exit 1
}
export FIRE4NIX_STARTUP_REPORT="$REPORT"
exec bash "$APP/scripts/validate_wpe_startup.sh"
"""

readme = """Fire4Nix One File Edition

1. Extract this ZIP directly into the ROCKNIX ports directory.
   Common layouts use /roms/ports/ or /storage/roms/ports/.
2. Keep Fire4Nix.sh next to the Fire4Nix/ directory.
3. Launch Fire4Nix.sh from Ports/EmulationStation.
4. Launch Teste-Fire4Nix.sh from Ports to run the preflight checks.
   It writes Fire4Nix-test-report.log beside the launcher.
5. Launch Validate-Fire4Nix.sh to verify launcher paths, certificates, Wayland, and modules.
   It writes Fire4Nix-startup-validation.log beside the launcher.
6. No root installer is required for this portable package.

Prerequisites:
- ROCKNIX RK3326 image (official 20260901 or newer)
- R36H/R36S or compatible device with ~1 GB RAM
- Wayland/Sway compositor running
- /dev/dri and sound device available

This package is emitted only when bin/fire4nix-wpe-platform is a real
ARM64/aarch64 ELF binary AND runtime/aarch64 contains the validated WPE WebKit
library plus WPEWebProcess, WPENetworkProcess and WPEGPUProcess, and their
static dependencies (including the launcher) resolve within the bundle or an
explicit target ROCKNIX sysroot. Required ELF version nodes are checked; individual symbols, dynamically loaded
plugins and graphics compatibility still need device validation. Runtime logs
and user data are created outside the ZIP contents through the Fire4Nix
configuration/runtime resolver.
"""

def zip_info(name: str, executable: bool = False):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    mode = stat.S_IFREG | (0o755 if executable else 0o644)
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info

def is_executable_runtime(rel: str) -> bool:
    return (
        rel.endswith(".sh")
        or rel.startswith("bin/")
        or "/libexec/" in rel
        or rel.endswith(".py")
    )

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    zf.writestr(zip_info("Fire4Nix.sh", True), root_launcher)
    zf.writestr(zip_info("Fire4Nix-README.txt", False), readme)
    zf.writestr(zip_info("Teste-Fire4Nix.sh", True), diagnostic_launcher)
    zf.writestr(zip_info("Validate-Fire4Nix.sh", True), startup_validator)
    zf.writestr(zip_info("Fire4Nix/dependency-report.json"),
                Path(os.environ["FIRE4NIX_DEPENDENCY_REPORT"]).read_bytes())

    for rel in required:
        src = root / rel
        arc = f"Fire4Nix/{rel}"
        info = zip_info(arc, is_executable_runtime(rel))
        zf.writestr(info, src.read_bytes())

    for tree in optional_trees:
        if not tree.is_dir():
            continue
        for src in sorted(p for p in tree.rglob("*") if p.is_file()):
            rel = src.relative_to(root).as_posix()
            arc = f"Fire4Nix/{rel}"
            zf.writestr(zip_info(arc, is_executable_runtime(rel)), src.read_bytes())

digest = hashlib.sha256(output.read_bytes()).hexdigest()
(output.parent / f"{output.name}.sha256").write_text(f"{digest}  {output.name}\n")
print(f"package={output}")
print(f"sha256={digest}")
PY

printf 'Fire4Nix One File package ready: %s\n' "$OUT"
printf 'SHA-256: '
cut -d' ' -f1 "$OUT.sha256"
