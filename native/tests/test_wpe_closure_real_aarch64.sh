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
# Both ELF64 PIE helpers carry the AArch64 dynamic linker even with -nostdlib.
grep -Fxq 'WPE_PT_INTERP_CHECKS=2' "$tmp/pass.txt"
grep -Fxq 'WPE_PT_INTERP_PROVEN_ON_R36H=no' "$tmp/pass.txt"
# Simulate the dlopen-only WPEInjectedBundle. It has no inbound DT_NEEDED,
# so recursive inspection must add it as a root from the strict asset report.
mkdir -p "$runtime/lib/wpe-webkit-2.0/injected-bundle" \
 "$runtime/share/wpe-webkit-2.0"
cat > "$tmp/injected.c" <<'EOF'
extern int step_symbol(void);
int wpe_injected_bundle_entry(void) { return step_symbol(); }
EOF
cc -shared -fPIC -nostdlib -Wl,-soname,libWPEInjectedBundle.so \
 "$tmp/injected.c" -Wl,--no-as-needed \
 -L"$sysroot/usr/lib" -l:libstep.so.1 \
 -o "$runtime/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
echo 'synthetic inspector fixture only' > "$runtime/share/wpe-webkit-2.0/inspector.gresource"
cat > "$runtime/BUILD-REPORT.txt" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
 --sdk-stage "$stage" --report "$tmp/strict-injected-pass.txt" --strict \
 > "$tmp/strict-injected-pass.log"
grep -Fxq 'WPE_INJECTED_BUNDLE_ELF_AUDITED=yes' "$tmp/strict-injected-pass.txt"
grep -Fxq 'WPE_INSTALLED_ASSETS_AUDIT=strict_assets_audited' "$tmp/strict-injected-pass.txt"
grep -Fxq 'WPE_SCANNED_ELFS=5' "$tmp/strict-injected-pass.txt"
grep -Fxq 'R36H_INSTALLABLE=no' "$tmp/strict-injected-pass.txt"
# Broken inspector data invalidates the strict runtime independently of ELF.
rm "$runtime/share/wpe-webkit-2.0/inspector.gresource"
set +e
python3 "$auditor" --runtime "$runtime" --sysroot "$sysroot" \
 --sdk-stage "$stage" --strict > "$tmp/strict-injected-missing.log" 2>&1
injected_rc=$?
set -e
test "$injected_rc" -eq 4
grep -Fq 'MISSING_UNSAFE_WPE_MODULE_OR_RESOURCE' "$tmp/strict-injected-missing.log"
# Restore legacy fixture profile for the remaining loader and SONAME cases.
rm -rf "$runtime/lib/wpe-webkit-2.0" "$runtime/share/wpe-webkit-2.0"
echo 'GPU_PROCESS_PROFILE=disabled_verified_wayland' > "$runtime/BUILD-REPORT.txt"

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

# Stage-only dependencies must be privately copied from the *exact* ARM64
# SDK overlay and the entire dynamic graph audited again, never host /usr.
bundler="$root/scripts/bundle-rocknix-wpe-sdk-deps.py"
bundled="$tmp/private-sdk-closed-runtime"
python3 "$bundler" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --output "$bundled" > "$tmp/bundle.log"
test -s "$bundled/lib/liboverlay.so.1"
cmp "$bundled/lib/liboverlay.so.1" "$stage/usr/lib/liboverlay.so.1"
grep -Fxq 'ROCKNIX_SDK_BUNDLED_LIBRARIES=1' "$bundled/SDK-BUNDLE-REPORT.txt"
grep -Fxq 'R36H_INSTALLABLE=no' "$bundled/SDK-BUNDLE-REPORT.txt"
grep -q 'lib/liboverlay.so.1' "$bundled/SHA256SUMS.txt"
(cd "$bundled" && sha256sum -c SHA256SUMS.txt > /dev/null)
python3 "$auditor" --runtime "$bundled" --sysroot "$sysroot" \
  --sdk-stage "$stage" --strict > "$tmp/closed.txt"
grep -Fxq 'WPE_RUNTIME_CLOSURE=SDK_STATIC_CANDIDATES_ONLY' "$tmp/closed.txt"
grep -Fxq 'WPE_STAGE_ONLY_DEPENDENCIES_COUNT=0' "$tmp/closed.txt"
# Inputs were never modified and outputs are immutable once created.
test ! -e "$runtime/lib/liboverlay.so.1"
if python3 "$bundler" --runtime "$runtime" --sysroot "$sysroot" \
  --sdk-stage "$stage" --output "$bundled" > /dev/null 2>&1; then
  echo 'ERROR: output bundle was silently overwritten' >&2; exit 1
fi

# A stage library carrying a temporary GitHub build RUNPATH must NOT be
# bundled even when its SONAME and architecture match the requested edge.
cc -shared -fPIC -nostdlib -Wl,-soname,liboverlay.so.1 \
 -Wl,-rpath,/home/runner/work/Fire4nix/build \
 "$tmp/overlay.c" -o "$stage/usr/lib/liboverlay.so.1"
set +e
python3 "$bundler" --runtime "$runtime" --sysroot "$sysroot" \
 --sdk-stage "$stage" --output "$tmp/untrusted-sdk-runtime" \
 > "$tmp/rejected-sdk.log" 2>&1
bad_rc=$?
set -e
test "$bad_rc" -eq 6
test ! -e "$tmp/untrusted-sdk-runtime"
grep -Eq 'UNSAFE_STAGE_ELF_RPATH|STATIC_CLOSURE_ERRORS' "$tmp/rejected-sdk.log"
echo 'WPE_PRIVATE_SDK_BUNDLE_FIXTURES=PASS_REAL_AARCH64_CLOSED_NO_HOST_LIBS'

echo 'WPE_REAL_AARCH64_ELF_FIXTURES=PASS_STATIC_RUNTIME_STAGE_ONLY_BLOCKS'
