#!/usr/bin/env bash
# Prove the cache uses the official AArch64 ROCKNIX compiler, never host gcc.
# A small C++ atomic object is sufficient; this does not compile WPE itself.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && -n "${GITHUB_WORKSPACE:-}" ]] || exit 4
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
compiler="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
test -x "$compiler"
test "$("$compiler" -dumpmachine)" = aarch64-rocknix-linux-gnu
test "$(command -v ccache)" = /usr/bin/ccache
test -n "${CCACHE_DIR:-}" && test -d "$CCACHE_DIR" && test ! -L "$CCACHE_DIR"
out="$GITHUB_WORKSPACE/ccache-cross-test"
mkdir -p "$out"
cat > "$out/atomics.cpp" <<'CPP'
#include <atomic>
static std::atomic<unsigned> counter{0};
extern "C" unsigned rocknix_ccache_probe() {
  return counter.fetch_add(1, std::memory_order_acq_rel);
}
CPP
export CCACHE_COMPILERCHECK=content
export CCACHE_BASEDIR="$GITHUB_WORKSPACE"
ccache --zero-stats > /dev/null
# Output file is NOT part of the compiled code's hash; repeat compilation
# with another filename and ensure a real cache hit occurred.
for name in one two; do
  ccache "$compiler" -O2 -std=c++17 -fPIC -mno-outline-atomics \
    -c "$out/atomics.cpp" -o "$out/$name.o"
  readelf -h "$out/$name.o" | grep -Eq 'Machine:[[:space:]]+AArch64'
  if "$sdk/bin/aarch64-rocknix-linux-gnu-nm" -u "$out/$name.o" | grep -q '__aarch64_'; then
    echo 'ERROR: cross compiler emitted outlined AArch64 atomic helpers' >&2
    exit 7
  fi
done
cmp "$out/one.o" "$out/two.o"
# Ubuntu 22.04 ships ccache 4.5.1, which supports --print-stats but
# not the later --format=json option.
ccache --print-stats > "$out/cache-stats.txt"
python3 - "$out/cache-stats.txt" <<'PY'
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    pairs = [line.split() for line in f if line.strip()]
stats = {fields[0]: int(fields[-1]) for fields in pairs if len(fields) >= 2
         and fields[-1].isdigit()}
hits = int(stats.get("cache_hit_direct", 0)) + int(stats.get("cache_hit_preprocessed", 0))
misses = int(stats.get("cache_miss", 0))
if hits < 1 or misses < 1:
    raise SystemExit(f"ERROR: expected cross compiler ccache miss and hit, got {stats}")
print(f"ROCKNIX_GCC15_CCACHE_HITS={hits}")
print(f"ROCKNIX_GCC15_CCACHE_MISSES={misses}")
PY
echo 'ROCKNIX_GCC15_CCACHE=PASS_CROSS_ARM64_OBJECTS_WITH_REAL_CACHE_HIT' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WEBKIT_COMPILED_IN_THIS_TEST=no' >> "$GITHUB_STEP_SUMMARY"
echo 'R36H_EXECUTED=no' >> "$GITHUB_STEP_SUMMARY"
