#!/usr/bin/env bash
# Inspect the real ROCKNIX RK3326 toolchain from GitHub Actions run 39525819979.
# Host-only, no target ELF execution, no source downloads or SD/firmware writes.
set -euo pipefail
mode=${1:---inspect}
case "$mode" in --inspect) ;; --help)
  echo 'Requires original run artifact, FIRE4NIX_TOOLCHAIN_ARCHIVE and GITHUB_WORKSPACE'; exit 0;;
  *) echo 'ERROR: use --inspect' >&2; exit 2;;
esac
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
workspace=${GITHUB_WORKSPACE:-}
archive=${FIRE4NIX_TOOLCHAIN_ARCHIVE:-}
reports=${FIRE4NIX_SDK_AUDIT_REPORTS:-}
[[ -n "$workspace" && -d "$workspace" && -n "$archive" && -f "$archive" ]] ||
  { echo 'ERROR: explicit real toolchain archive and GitHub workspace required' >&2; exit 4; }
[[ -n "$reports" && ${GITHUB_ACTIONS:-} == true ]] ||
  { echo 'ERROR: run only in isolated GitHub Actions workspace' >&2; exit 4; }
workspace=$(cd -- "$workspace" && pwd -P)
case "$workspace" in */Fire4nix/Fire4nix) ;; *)
  echo 'ERROR: checkpoint toolchain embeds the original GitHub runner path' >&2; exit 4;;
esac
[[ "$archive" == "$workspace/recovered-checkpoint/rocknix-toolchain-host-only.tar.xz" ]] ||
  { echo 'ERROR: unexpected archive location' >&2; exit 4; }
[[ "$reports" == "$workspace/sdk-audit-reports" ]] ||
  { echo 'ERROR: audit reports must stay inside workspace' >&2; exit 4; }
[[ "${FIRE4NIX_ORIGINAL_RUN_ID:-}" == 39525819979 ]] ||
  { echo 'ERROR: unverified checkpoint run selection' >&2; exit 4; }
for cmd in tar python3 readelf cmake ninja pkg-config sha256sum; do
  command -v "$cmd" >/dev/null || { echo "ERROR: required host command absent: $cmd" >&2; exit 4; }
done
mkdir -p "$reports"
sdk_build="$workspace/rocknix-source/build.ROCKNIX-RK3326.aarch64"
sdk="$sdk_build/toolchain"
[[ ! -e "$sdk" ]] || { echo 'ERROR: refuse to overwrite a prior SDK directory' >&2; exit 4; }
# Refuse archive entries with paths outside toolchain/; no shell evaluation from tar.
python3 - "$archive" <<'PY'
import pathlib
import sys
import tarfile
archive = pathlib.Path(sys.argv[1])
with tarfile.open(archive, 'r:xz') as tf:
    entries = tf.getmembers()
    if not entries or len(entries) > 200000:
        raise SystemExit('ERROR: empty/oversized checkpoint tar file list')
    for m in entries:
        p = pathlib.PurePosixPath(m.name)
        if p.is_absolute() or not p.parts or p.parts[0] != 'toolchain' or '..' in p.parts:
            raise SystemExit('ERROR: checkpoint includes entry outside toolchain/: ' + m.name)
        if m.issym() and pathlib.PurePosixPath(m.linkname).is_absolute():
            # Existing SDK may contain absolute symlinks; require explicit review,
            # never extract a symlink that might point into the runner host.
            raise SystemExit('ERROR: checkpoint has absolute symlink: ' + m.name)
        if m.islnk() and (pathlib.PurePosixPath(m.linkname).is_absolute()
                         or '..' in pathlib.PurePosixPath(m.linkname).parts):
            raise SystemExit('ERROR: unsafe hardlink: ' + m.name)
print('CHECKPOINT_TAR_LAYOUT=PASS_RELATIVE_TOOLCHAIN_ONLY')
PY
mkdir -p "$sdk_build"
tar -xJf "$archive" -C "$sdk_build" --no-same-owner --no-same-permissions
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
cxx="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
toolchain="$sdk/fire4nix-toolchain.cmake"
[[ -x "$cc" && -x "$cxx" && -d "$sysroot" && -f "$toolchain" ]] ||
  { echo 'ERROR: checkpoint SDK missing cross compiler/sysroot/CMake toolchain' >&2; exit 5; }
"$cc" -dumpmachine > "$reports/target-triple.txt"
grep -Fxq 'aarch64-rocknix-linux-gnu' "$reports/target-triple.txt"
"$cc" --version | head -n 1 > "$reports/compiler-version.txt"
FIRE4NIX_ROCKNIX_RELEASE=20260801 FIRE4NIX_ROCKNIX_TOOLCHAIN="$toolchain" \
  FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/check-rocknix-sdk.sh" --check > "$reports/sdk-preflight.txt"
grep -Fxq 'SDK_PREFLIGHT=PASS' "$reports/sdk-preflight.txt"
FIRE4NIX_ROCKNIX_RELEASE=20260801 FIRE4NIX_ROCKNIX_TOOLCHAIN="$toolchain" \
  FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/check-rocknix-compiler.sh" --check > "$reports/compiler-preflight.txt"
grep -Fxq 'COMPILER_PREFLIGHT=PASS' "$reports/compiler-preflight.txt"
# The real sysroot is mostly glibc/toolchain at this point. Report shortages
# as data, not as a false-success WPE build.
FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/audit-wpe-sysroot-pkgconfig.sh" --inspect \
  > "$reports/wpe-pkgconfig-real-sysroot.txt"
ok=$(grep -c '^TARGET_PC_OK=' "$reports/wpe-pkgconfig-real-sysroot.txt" || true)
missing=$(grep -c '^TARGET_PC_MISSING_OR_OLD=' "$reports/wpe-pkgconfig-real-sysroot.txt" || true)
result=$(sed -n 's/^SYSROOT_PC_AUDIT=//p' "$reports/wpe-pkgconfig-real-sysroot.txt" | tail -n 1)
[[ -n "$result" ]] || { echo 'ERROR: WPE metadata auditor did not emit status' >&2; exit 5; }
{
  echo 'REAL_SDK_CHECKPOINT=PASS_RESTORED_AND_C_CXX_LINKED'
  echo 'ROCKNIX_RELEASE=20260801'
  echo 'ABI=AARCH64'
  echo 'GLIBC_MAX=2.41'
  echo 'SOURCE_RUN_ID=39525819979'
  echo "TARGET_PC_OK_COUNT=$ok"
  echo "TARGET_PC_MISSING_OR_OLD_COUNT=$missing"
  echo "SYSROOT_PC_AUDIT=$result"
  echo 'WEBKIT_BUILT=no'
  echo 'WEBKIT_RENDERING_TESTED=no'
  echo 'R36H_INSTALLABLE=no'
  echo 'NEXT_ACTION=BUILD_DEPENDENCIES_IN_REAL_ROCKNIX_SYSROOT'
} > "$reports/SDK-READINESS.txt"
cat "$reports/SDK-READINESS.txt"
