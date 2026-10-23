#!/usr/bin/env bash
# Fast, real ROCKNIX 20260801 RK3326 GCC-15 AArch64 atomic ABI experiment.
# Never execute target binaries and never copy libgcc from Ubuntu.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && -n "$GITHUB_WORKSPACE" ]] || {
  echo "ERROR: GitHub Actions workspace required" >&2; exit 4;
}
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cxx="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
gcc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
nm="$sdk/bin/aarch64-rocknix-linux-gnu-nm"
test -x "$cxx" && test -x "$gcc" && test -x "$nm"
test "$("$gcc" -dumpmachine)" = "aarch64-rocknix-linux-gnu"
out="$GITHUB_WORKSPACE/atomic-test-results"
mkdir -p "$out"
cat > "$out/atomics.cpp" <<'CPP'
#include <atomic>
#include <cstdint>
static std::atomic<uint32_t> count32{0};
static std::atomic<uint64_t> count64{0};
extern "C" uint32_t r36h_atomic_add_32() { return count32.fetch_add(3, std::memory_order_acq_rel); }
extern "C" uint64_t r36h_atomic_add_64() { return count64.fetch_add(5, std::memory_order_acq_rel); }
extern "C" bool r36h_atomic_cas_64(uint64_t old) { return count64.compare_exchange_strong(old, 5); }
CPP
{
  echo "ATOMIC_TARGET=$("$gcc" -dumpmachine)"
  echo "ATOMIC_GCC_VERSION=$("$gcc" -dumpfullversion)"
  echo "LIBGCC_A=$("$gcc" -print-libgcc-file-name)"
  echo "LIBGCC_S=$("$gcc" -print-file-name=libgcc_s.so.1)"
  echo "COMPILER_FLAGS=-mcpu=cortex-a35+crc+fp+simd -mno-outline-atomics"
} | tee "$out/provenance.txt"
libgcc=$("$gcc" -print-libgcc-file-name)
test -f "$libgcc" || { echo "ERROR: target libgcc archive missing" >&2; exit 6; }
"$nm" -g "$libgcc" > "$out/libgcc-symbols.txt" 2>&1 || true
grep -E '__aarch64_(ldadd|cas|swp)' "$out/libgcc-symbols.txt" | head -n 24 > "$out/libgcc-atomic-helpers.txt" || true

for profile in outline no-outline; do
  if [ "$profile" = outline ]; then option=-moutline-atomics; else option=-mno-outline-atomics; fi
  "$cxx" --sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot" \
    -mcpu=cortex-a35+crc+fp+simd "$option" -O3 -fPIC -std=c++17 \
    -c "$out/atomics.cpp" -o "$out/$profile.o"
  "$nm" -u "$out/$profile.o" > "$out/$profile-undefined.txt" || true
  echo "ATOMIC_UNDEF_$profile=$(grep -c '__aarch64_' "$out/$profile-undefined.txt" || true)" | tee -a "$out/provenance.txt"
  set +e
  "$cxx" --sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot" \
    -mcpu=cortex-a35+crc+fp+simd "$option" \
    -Wl,--no-undefined -shared \
    "$out/$profile.o" -o "$out/libatomic-$profile.so" \
    > "$out/link-$profile.log" 2>&1
  rc=$?
  set -e
  echo "ATOMIC_LINK_$profile-EXIT=$rc" | tee -a "$out/provenance.txt"
done
test -s "$out/libatomic-no-outline.so" || {
  echo "ERROR: -mno-outline-atomics cross shared link failed" >&2
  cat "$out/link-no-outline.log" >&2
  exit 9
}
if grep -q '__aarch64_' "$out/no-outline-undefined.txt"; then
  echo "ERROR: no-outline still requires AArch64 outlined atomic helpers" >&2; exit 10
fi
readelf -h "$out/libatomic-no-outline.so" > "$out/no-outline-elf.txt"
readelf -d "$out/libatomic-no-outline.so" > "$out/no-outline-dynamic.txt"
readelf -V "$out/libatomic-no-outline.so" > "$out/no-outline-glibc.txt"
grep -Eq 'Machine:[[:space:]]+AArch64' "$out/no-outline-elf.txt"
grep -Eq 'Class:[[:space:]]+ELF64' "$out/no-outline-elf.txt"
if grep -E 'Name: GLIBC_(2\.(4[2-9]|[5-9][0-9])|[3-9]\.)' "$out/no-outline-glibc.txt"; then
  echo "ERROR: linked ELF requires GLIBC newer than 2.41" >&2; exit 10
fi
echo "ROCKNIX_GCC15_NO_OUTLINE_ATOMICS=PASS_REAL_AARCH64_LINK" | tee -a "$out/provenance.txt"
echo 'TARGET_EXECUTED=no' | tee -a "$out/provenance.txt"
cat "$out/provenance.txt" >> "$GITHUB_STEP_SUMMARY"
