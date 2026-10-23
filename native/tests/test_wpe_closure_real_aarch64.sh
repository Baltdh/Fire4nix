#!/usr/bin/env bash
# Compile authentic AArch64 ELF fixtures and execute only the HOST readelf audit.
# No target binaries are ever launched, and this is not a WPE/WebKit build.
set -euo pipefail
[[ "$(uname -m)" == aarch64 ]] || { echo 'ERROR: genuine ARM64 runner required' >&2; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
auditor="$root/scripts/audit-wpe-runtime-closure.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
runtime="$tmp/runtime"
sysroot="$tmp/rocknix-sysroot-fixture"
stage="$tmp/stage1-fixture"
mkdir -p "$runtime/lib" "$runtime/libexec/wpe-webkit-2.0" \
  "$sysroot/lib" "$sysroot/usr/lib" "$stage/usr/lib"

# PT_INTERP must resolve to a genuine AArch64 ELF inside the target
# sysroot. This test provides a standalone -nostdlib synthetic loader, not
# a copy of Ubuntu glibc or an actual ROCKNIX device runtime.
cat > "$tmp/loader.c" <<'EOF'
int fixture_dynamic_loader(void) { return 0; }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,ld-linux-aarch64.so.1 \
  "$tmp/loader.c" -o "$sysroot/lib/ld-linux-aarch64.so.1"
readelf -h "$sysroot/lib/ld-linux-aarch64.so.1" |
  grep -Eq 'Machine:[[:space:]]*AArch64'

# No host glibc or other Ubuntu libraries are used as a runtime dependency.
# -nostdlib keeps the synthetic fixture graph to exactly controlled SONAMEs.
cat > "$tmp/step.c" <<'EOF'
int step_symbol(void) { return 7; }
EOF
cc -shared -fPIC -nostdlib \
  -Wl,-soname,libstep.so.1 "$tmp/step.c" \
  -o "$sysroot/usr/lib/libstep.so.1"
cat > "$tmp/webkit.c" <<'EOF'
extern int step_symbol(void);
int webkit_web_view_get_wpe_view(void) { return step_symbol(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEWebKit-2.0.so.1 \
  "$tmp/webkit.c" -Wl,--no-as-needed -L"$sysroot/usr/lib" -l:libstep.so.1 \
  -o "$runtime/lib/libWPEWebKit-2.0.so.1"
cat > "$tmp/web.c" <<'EOF'
extern int webkit_web_view_get_wpe_view(void);
int _start(void) { return webkit_web_view_get_wpe_view(); }
EOF
cc -nostdlib -fno-stack-protector -Wl,-e,_start \
  "$tmp/web.c" -Wl,--no-as-needed -L"$runtime/lib" -l:libWPEWebKit-2.0.so.1 \
  -Wl,-rpath-link,"$sysroot/usr/lib" \
  -o "$runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
cat > "$tmp/network.c" <<'EOF'
int _start(void) { return 0; }
EOF
cc -nostdlib -fno-stack-protector -Wl,-e,_start "$tmp/network.c" \
  -o "$runtime/libexec/wpe-webkit-2.0/WPENetworkProcess"
echo 'GPU_PROCESS_PROFILE=disabled_verified_wayland' > "$runtime/BUILD-REPORT.txt"
for elf in "$runtime/lib/libWPEWebKit-2.0.so.1" \
  "$runtime/libexec/wpe-webkit-2.0/WPEWebProcess" \
  "$runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" \
  "$sysroot/usr/lib/libstep.so.1"; do
  readelf -h "$elf" | grep -Eq 'Machine:[[:space:]]*AArch64'
  readelf -h "$elf" | grep -Eq 'Class:[[:space:]]*ELF64'
done
readelf -d "$runtime/lib/libWPEWebKit-2.0.so.1" |
  grep -Fq 'Shared library: [libstep.so.1]'
readelf -d "$runtime/libexec/wpe-webkit-2.0/WPEWebProcess" |
  grep -Fq 'Shared library: [libWPEWebKit-2.0.so.1]'

python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --report "$tmp/pass.txt" --strict > "$tmp/pass.log"
grep -Fxq 'WPE_RUNTIME_CLOSURE=SDK_STATIC_CANDIDATES_ONLY' "$tmp/pass.txt"
grep -Fxq 'WPE_STAGE_ONLY_DEPENDENCIES_COUNT=0' "$tmp/pass.txt"
grep -Fxq 'WPE_MISSING_SONAMES_COUNT=0' "$tmp/pass.txt"
grep -Fxq 'WPE_PT_INTERP_CHECKS=1' "$tmp/pass.txt"
grep -Fxq 'WPE_PT_INTERP_PROVEN_ON_R36H=no' "$tmp/pass.txt"
# Removing the runtime loader from the target sysroot blocks an otherwise
# valid WPEWebProcess binary before it can be treated as deployable.
mv "$sysroot/lib/ld-linux-aarch64.so.1" "$tmp/loader-hidden.so.1"
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/missing-loader.log"
loader_rc=$?
set -e
test "$loader_rc" -eq 6
grep -Fq 'MISSING_SYSROOT_PT_INTERP:WPEWebProcess' "$tmp/missing-loader.log"
mv "$tmp/loader-hidden.so.1" "$sysroot/lib/ld-linux-aarch64.so.1"

grep -Fxq 'R36H_INSTALLABLE=no' "$tmp/pass.txt"

# Without libstep in ROCKNIX's fixture, a transitive missing SONAME blocks.
mv "$sysroot/usr/lib/libstep.so.1" "$tmp/step-hidden.so.1"
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/missing.log"
missing_rc=$?
set -e
test "$missing_rc" -eq 6
grep -Fxq 'WPE_RUNTIME_CLOSURE=BLOCKED' "$tmp/missing.log"
grep -Fq 'libWPEWebKit-2.0.so.1:libstep.so.1' "$tmp/missing.log"
mv "$tmp/step-hidden.so.1" "$sysroot/usr/lib/libstep.so.1"

# Compile a valid ELF found ONLY in the build-stage overlay. It is never a
# proof that the user console supplies it; the direct --strict CLI must fail.
cat > "$tmp/overlay.c" <<'EOF'
int overlay_symbol(void) { return 9; }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,liboverlay.so.1 \
  "$tmp/overlay.c" -o "$stage/usr/lib/liboverlay.so.1"
cat > "$tmp/step.c" <<'EOF'
extern int overlay_symbol(void);
int step_symbol(void) { return overlay_symbol(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libstep.so.1 "$tmp/step.c" \
  -Wl,--no-as-needed -L"$stage/usr/lib" -l:liboverlay.so.1 \
  -o "$sysroot/usr/lib/libstep.so.1"
readelf -d "$sysroot/usr/lib/libstep.so.1" |
  grep -Fq 'Shared library: [liboverlay.so.1]'
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/overlay.log"
overlay_rc=$?
set -e
test "$overlay_rc" -eq 6
grep -Fxq 'WPE_RUNTIME_CLOSURE=BLOCKED' "$tmp/overlay.log"
grep -Fxq 'WPE_STAGE_ONLY_DEPENDENCIES_COUNT=1' "$tmp/overlay.log"
grep -Fq 'WPE_STAGE_ONLY_DEPENDENCIES=libstep.so.1:liboverlay.so.1' "$tmp/overlay.log"
grep -Fxq 'R36H_INSTALLABLE=no' "$tmp/overlay.log"
echo 'WPE_REAL_AARCH64_ELF_FIXTURES=PASS_STATIC_RUNTIME_STAGE_ONLY_BLOCKS'
