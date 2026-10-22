#!/usr/bin/env bash
# Build real WebProcess + NetworkProcess from a configured WPE 2.54.1 source.
# --check is read-only and permits host fixture testing. --build is CI-only.
# Never execute AArch64 programs or install anything on the R36H.
set -euo pipefail
mode="${1:---help}"
case "$mode" in --check|--build) ;; *)
  echo "Usage: $0 --check|--build" >&2; exit 2 ;;
esac
if [[ "$mode" == "--build" ]]; then
  [[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" -ne 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
    echo 'ERROR: subprocess compilation requires non-root GitHub Actions' >&2; exit 4;
  }
  root="$GITHUB_WORKSPACE"
  work="$root/wpe-unified-sdk-build"
  repo_root="$root/fire4nix"
else
  work="${FIRE4NIX_WPE_BUILD_WORK:-}"
  [[ -n "$work" && -d "$work" ]] || {
    echo 'ERROR: set FIRE4NIX_WPE_BUILD_WORK for --check' >&2; exit 4;
  }
  repo_root=""
fi
build="$work/configure"
report="$work/report"
cache="$build/CMakeCache.txt"
[[ -s "$build/build.ninja" && -s "$cache" ]] || {
  echo 'ERROR: full WPE Ninja/CMake configuration required' >&2; exit 5;
}
for expected in 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' \
 'ENABLE_GPU_PROCESS:BOOL=OFF' 'USE_GSTREAMER:BOOL=OFF' \
 'USE_GBM:BOOL=OFF' 'USE_LIBDRM:BOOL=OFF'; do
  grep -Fxq "$expected" "$cache" || {
    echo "ERROR: unexpected CMake option: $expected" >&2; exit 5;
  }
done
# WebKit 2.54.1 declares source CMake targets WebProcess and NetworkProcess,
# and PlatformWPE changes their executable output names to WPE*Process.
target_file=$(mktemp)
trap 'rm -f "$target_file"' EXIT
ninja -C "$build" -t targets all > "$target_file"
for target in WebKit WebProcess NetworkProcess; do
  grep -Eq "^$target:[[:space:]]" "$target_file" || {
    echo "ERROR: real WPE Ninja target missing: $target" >&2; exit 6;
  }
done
echo 'WPE_REQUIRED_TARGETS=WebKit,WebProcess,NetworkProcess'
echo 'WPE_GPU_PROCESS=OFF_VERIFIED'
if [[ "$mode" == "--check" ]]; then
  echo 'WPE_SUBPROCESS_TARGET_CHECK=PASS_STATIC'
  echo 'WPE_PROCESS_BINARIES_BUILT=no'
  exit 0
fi

[[ -s "$report/status.txt" && -s "$report/merge.txt" ]] || {
  echo 'ERROR: prior genuine ROCKNIX CMake/SDK proof missing' >&2; exit 7;
}
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' "$report/merge.txt"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ -x "$cc" && "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || {
  echo 'ERROR: wrong target compiler' >&2; exit 7;
}
result="$report/wpe-subprocesses-result.txt"
echo 'WPE_SUBPROCESS_BUILD=START_REAL_ROCKNIX_AARCH64' | tee "$result"
set +e
timeout --signal=TERM --kill-after=20s 10800s \
 cmake --build "$build" --target WebProcess NetworkProcess --parallel 2 \
 > "$report/wpe-subprocesses-build.log" 2>&1
rc=$?
set -e
echo "WPE_SUBPROCESS_CMAKE_EXIT=$rc" | tee -a "$result"
if (( rc != 0 )); then
  echo 'WPE_SUBPROCESS_BUILD=BLOCKED' | tee -a "$result"
  grep -E -A 7 'FAILED:|fatal error:|error:|undefined reference|ninja: build stopped|Killed' \
    "$report/wpe-subprocesses-build.log" | head -n 150 \
    > "$report/wpe-subprocesses-first-errors.txt" || true
  cat "$report/wpe-subprocesses-first-errors.txt"
  tail -n 60 "$report/wpe-subprocesses-build.log"
  exit 10
fi
for process in WPEWebProcess WPENetworkProcess; do
  found=""
  while IFS= read -r -d '' item; do
    if readelf -h "$item" 2>/dev/null | grep -Eq 'Machine:[[:space:]]+AArch64'; then
      found="$item"; break
    fi
  done < <(find "$build" -type f -name "$process" -print0)
  [[ -n "$found" ]] || {
    echo "ERROR: missing real AArch64 ELF for $process" >&2; exit 11;
  }
  readelf -h "$found" | grep -Eq 'Class:[[:space:]]+ELF64'
  readelf -h "$found" | grep -Eq 'Data:.*little endian'
  if readelf -d "$found" | grep -E '\((RPATH|RUNPATH)\).* \[/' >/dev/null; then
    echo "ERROR: $process contains host absolute RPATH" >&2; exit 11;
  fi
  python3 - "$found" <<'PY'
import re, subprocess, sys
versions = subprocess.check_output(["readelf", "-V", sys.argv[1]], text=True)
need = [(int(a),int(b)) for a,b in re.findall(r'Name:\s*GLIBC_(\d+)\.(\d+)', versions)]
if any(ver > (2,41) for ver in need):
    raise SystemExit("ERROR: process demands newer GLIBC than 2.41")
PY
  echo "WPE_PROCESS_VERIFIED=$process"
done

dest="$work/private-wpe-destdir"
[[ ! -e "$dest" && ! -L "$dest" ]] || {
  echo 'ERROR: DESTDIR already exists' >&2; exit 12;
}
mkdir -p "$dest"
set +e
DESTDIR="$dest" cmake --install "$build" --prefix /usr \
 > "$report/wpe-subprocesses-install.log" 2>&1
rc=$?
set -e
if (( rc != 0 )); then
  echo 'WPE_PRIVATE_DESTDIR_INSTALL=BLOCKED' | tee -a "$result"
  tail -n 80 "$report/wpe-subprocesses-install.log"
  exit 12
fi
runtime="$work/private-wpe-runtime"
FIRE4NIX_WPE_DESTDIR="$dest" \
FIRE4NIX_WPE_RUNTIME_OUT="$runtime" \
FIRE4NIX_WPE_CMAKE_CACHE="$cache" \
FIRE4NIX_REQUIRE_MEDIA_FREE=1 \
FIRE4NIX_TARGET_GLIBC_MAX=2.41 \
sh "$repo_root/rocknix-integration/stage-wpe-runtime.sh" --stage \
 > "$report/wpe-subprocesses-stage.log" 2>&1 || {
   echo 'WPE_PRIVATE_RUNTIME_STAGE=BLOCKED' | tee -a "$result"
   tail -n 100 "$report/wpe-subprocesses-stage.log"
   exit 13
 }
test -s "$runtime/lib/libWPEWebKit-2.0.so.1"
for p in WPEWebProcess WPENetworkProcess; do
  test -s "$runtime/libexec/wpe-webkit-2.0/$p"
done
test ! -e "$runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
grep -Fxq 'GPU_PROCESS_PROFILE=disabled_verified_wayland' "$runtime/BUILD-REPORT.txt"
(cd "$runtime" && sha256sum -c SHA256SUMS.txt)
{
  echo 'WPE_SUBPROCESS_BUILD=PASS_REAL_AARCH64'
  echo 'WPE_PRIVATE_RUNTIME_STAGE=PASS_STATIC_GATES'
  echo 'WPE_TRANSITIVE_ABI_PROVEN=no'
  echo 'WPE_GRAPHICAL_RUNTIME_TESTED=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee -a "$result"
cat "$result" >> "$GITHUB_STEP_SUMMARY"
