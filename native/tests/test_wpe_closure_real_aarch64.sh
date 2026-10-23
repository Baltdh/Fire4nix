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
# Model WPE 2.54.1's separately dlopen'd injected-bundle ELF.
# Deliberately include a target SONAME dependency so recursive closure must
# follow the bundle even if no other binary contains it in DT_NEEDED.
mkdir -p "$runtime/lib/wpe-webkit-2.0/injected-bundle" "$runtime/share/wpe-webkit-2.0"
cat > "$tmp/injected.c" <<'EOF'
extern int step_symbol(void);
int injected_entrypoint(void) { return step_symbol(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
  "$tmp/injected.c" -Wl,--no-as-needed \
  -L"$sysroot/usr/lib" -l:libstep.so.1 \
  -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
printf 'GResource fixture only\\n' > "$runtime/share/wpe-webkit-2.0/inspector.gresource"
cat > "$runtime/BUILD-REPORT.txt" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
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
grep -Fxq 'WPE_INJECTED_BUNDLE_INCLUDED_IN_CLOSURE=yes' "$tmp/pass.txt"
grep -Fxq 'WPE_SCANNED_ELFS=5' "$tmp/pass.txt"
grep -Fxq 'WPE_MISSING_SONAMES_COUNT=0' "$tmp/pass.txt"
# Both ELF64 PIE helpers carry the AArch64 dynamic linker even with -nostdlib.
grep -Fxq 'WPE_PT_INTERP_CHECKS=2' "$tmp/pass.txt"
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

# Injected bundle has a separate dependency graph not listed in the core
# WebKit shared object's own DT_NEEDED. A missing module-only dependency is
# still fatal to strict runtime staging.
cat > "$tmp/injected.c" <<'EOF'
extern int missing_injected(void);
int injected_entrypoint(void) { return missing_injected(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
  "$tmp/injected.c" -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/injected-missing.log"
injected_rc=$?
set -e
# An unresolved shared-library symbol alone is not a DT_NEEDED edge: add
# a genuine separate shared object, linked into the injected bundle.
cat > "$tmp/injecteddep.c" <<'EOF'
int missing_injected(void) { return 13; }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libinjecteddep.so.1 \
  "$tmp/injecteddep.c" -o "$tmp/libinjecteddep.so.1"
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
  "$tmp/injected.c" -Wl,--no-as-needed -L"$tmp" -l:libinjecteddep.so.1 \
  -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
readelf -d "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" |
  grep -Fq 'Shared library: [libinjecteddep.so.1]'
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/injected-needed.log"
injected_needed_rc=$?
set -e
test "$injected_needed_rc" -eq 6
grep -Fq 'libWPEInjectedBundle.so:libinjecteddep.so.1' "$tmp/injected-needed.log"
# Restore the authentic injected fixture before exercising other branches.
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
  "$tmp/injected.c" -o "$tmp/replaced-injected-unsafe.so"
cat > "$tmp/injected.c" <<'EOF'
extern int step_symbol(void);
int injected_entrypoint(void) { return step_symbol(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
  "$tmp/injected.c" -Wl,--no-as-needed \
  -L"$sysroot/usr/lib" -l:libstep.so.1 \
  -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"

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
