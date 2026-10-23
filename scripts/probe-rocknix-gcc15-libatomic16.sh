#!/usr/bin/env bash
# Investigate the actual GCC 15.2 ROCKNIX AArch64 libatomic16 link failure.
# Compiles only tiny AArch64 fixtures and NEVER runs target ELF.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && -n "${GITHUB_WORKSPACE:-}" ]] || {
 echo 'ERROR: this probe requires the genuine GitHub ROCKNIX SDK' >&2; exit 4;
}
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
nm="$sdk/bin/aarch64-rocknix-linux-gnu-nm"
test -x "$cc" && test -x "$nm"
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
out="$GITHUB_WORKSPACE/atomic16-link-evidence"
mkdir -p "$out"
atomic=$("$cc" -print-file-name=libatomic.so.1)
printf 'ROCKNIX_GCC_TARGET=%s\nLIBATOMIC_PRINT_PATH=%s\n' "$("$cc" -dumpmachine)" "$atomic" > "$out/provenance.txt"
if [[ ! -f "$atomic" || "$atomic" == libatomic.so.1 ]]; then
  echo 'ERROR: GCC cannot resolve target libatomic.so.1' >&2
  find "$sdk" -name 'libatomic.so*' -print | head -n 20 || true
  exit 5
fi
atomic=$(realpath -e "$atomic")
case "$atomic" in "$sdk"/*) ;; *) echo 'ERROR: target libatomic outside pinned SDK' >&2; exit 6 ;; esac
dir=$(dirname "$atomic")
echo "LIBATOMIC_TARGET_REALPATH=$atomic" >> "$out/provenance.txt"
readelf -h "$atomic" > "$out/libatomic-elf.txt"
readelf -d "$atomic" > "$out/libatomic-dynamic.txt"
readelf --wide -V "$atomic" > "$out/libatomic-glibc.txt"
readelf --wide --dyn-syms "$atomic" > "$out/libatomic-symbols.txt"
grep -Eq 'Machine:[[:space:]]+AArch64' "$out/libatomic-elf.txt"
grep -Eq 'Class:[[:space:]]+ELF64' "$out/libatomic-elf.txt"
grep -Eq 'SONAME.*\[libatomic.so.1\]' "$out/libatomic-dynamic.txt"
grep -Fq '__atomic_load_16' "$out/libatomic-symbols.txt"
grep -Fq '__atomic_store_16' "$out/libatomic-symbols.txt"
python3 - "$out/libatomic-glibc.txt" <<'PY'
import pathlib, re, sys
text=pathlib.Path(sys.argv[1]).read_text()
versions=[(int(a),int(b)) for a,b in re.findall(r'Name:\s*GLIBC_(\d+)\.(\d+)', text)]
if any(x>(2,41) for x in versions):
  raise SystemExit('ERROR: target libatomic requires GLIBC >2.41')
print('LIBATOMIC_TARGET_GLIBC=WITHIN_2_41')
PY
cat > "$out/fixture.c" <<'EOF'
typedef unsigned __int128 uint128;
static uint128 storage;
void wpe_atomic16_store(uint128 value) { __atomic_store_n(&storage, value, __ATOMIC_RELEASE); }
uint128 wpe_atomic16_load(void) { return __atomic_load_n(&storage, __ATOMIC_ACQUIRE); }
EOF
"$cc" -O2 -fPIC -mno-outline-atomics -shared -Wl,-z,defs \
 -Wl,-soname,libwpe-atomic-fixture.so.1 \
 "$out/fixture.c" -latomic -o "$out/libwpe-atomic-fixture.so.1"
readelf -d "$out/libwpe-atomic-fixture.so.1" > "$out/fixture-needed.txt"
grep -Eq 'NEEDED.*\[libatomic.so.1\]' "$out/fixture-needed.txt"
cat > "$out/main.c" <<'EOF'
typedef unsigned __int128 uint128;
extern void wpe_atomic16_store(uint128);
extern uint128 wpe_atomic16_load(void);
int main(void) { wpe_atomic16_store((uint128)42); return wpe_atomic16_load()!=42; }
EOF
# Reproduce the exact WebProcess scenario: linking an executable against a
# WebKit-like DSO whose DT_NEEDED contains target libatomic.so.1.
"$cc" -O2 -mno-outline-atomics \
 -Wl,-rpath-link,"$dir" -Wl,-rpath-link,"$sdk/aarch64-rocknix-linux-gnu/sysroot/usr/lib" \
 "$out/main.c" -L"$out" -Wl,--no-as-needed \
 -l:libwpe-atomic-fixture.so.1 -o "$out/WPEWebProcess-atomic16-fixture"
readelf -h "$out/WPEWebProcess-atomic16-fixture" > "$out/executable-elf.txt"
grep -Eq 'Machine:[[:space:]]+AArch64' "$out/executable-elf.txt"
{
 echo 'LIBATOMIC16_LINK=PASS_REAL_ROCKNIX_GCC15_ARM64'
 echo "LIBATOMIC16_RPATH_LINK=$dir"
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_REAL_MOTOR_BUILT=no'
} | tee -a "$out/provenance.txt" "$GITHUB_STEP_SUMMARY"
