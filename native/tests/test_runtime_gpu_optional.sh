#!/bin/sh
# Offline tests for WPE runtime GPU profile; no AArch64 code is executed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/staged/usr/lib" "$T/staged/usr/libexec/wpe-webkit-2.0" "$T/fakebin"
printf 'fixture engine\n' > "$T/staged/usr/lib/libWPEWebKit-2.0.so.1"
for proc in WPEWebProcess WPENetworkProcess; do
  printf 'fixture %s\n' "$proc" > "$T/staged/usr/libexec/wpe-webkit-2.0/$proc"
done
cat > "$T/fakebin/readelf" <<'READELF'
#!/bin/sh
case " $* " in
  *" -h "*)
    printf '%s\n' 'Class: ELF64' 'Data: 2'"'"'s complement, little endian' 'Machine: AArch64'
    ;;
  *" -V "*)
    echo 'Name: GLIBC_2.41  Flags: none'
    ;;
  *" --dyn-syms "*)
    echo '123: 00000000 0 FUNC GLOBAL DEFAULT 1 webkit_web_view_get_wpe_view'
    ;;
  *" -d "*)
    echo '0x1 (NEEDED) Shared library: [libc.so.6]'
    ;;
  *) echo "unexpected readelf invocation: $*" >&2; exit 3 ;;
esac
READELF
chmod +x "$T/fakebin/readelf"
STAGER="$ROOT/rocknix-integration/stage-wpe-runtime.sh"
export PATH="$T/fakebin:$PATH"
export FIRE4NIX_WPE_DESTDIR="$T/staged"
export FIRE4NIX_REQUIRE_MEDIA_FREE=1
export FIRE4NIX_WPE_GPU_PROCESS=disabled
FIRE4NIX_WPE_RUNTIME_OUT="$T/no-gpu" sh "$STAGER" --stage > "$T/no-gpu.log"
grep -Fxq 'GPU_PROCESS=disabled' "$T/no-gpu/GPU-PROFILE.txt"
test ! -e "$T/no-gpu/libexec/wpe-webkit-2.0/WPEGPUProcess"
(cd "$T/no-gpu" && sha256sum -c SHA256SUMS.txt >/dev/null)
grep -Fxq 'PROFILE=MEDIA_FREE VERIFIED' "$T/no-gpu/MEDIA-PROFILE.txt"

# Old/default mode must not silently accept a missing GPU helper.
set +e
FIRE4NIX_WPE_GPU_PROCESS=required FIRE4NIX_WPE_RUNTIME_OUT="$T/required-missing" \
  sh "$STAGER" --stage > "$T/required-missing.log" 2>&1
rc=$?
set -e
test "$rc" -eq 3
test ! -e "$T/required-missing"
grep -Fq 'missing staged WPEGPUProcess' "$T/required-missing.log"

# Unknown profile values are rejected before any runtime is created.
set +e
FIRE4NIX_WPE_GPU_PROCESS=invalid FIRE4NIX_WPE_RUNTIME_OUT="$T/invalid" \
  sh "$STAGER" --stage > "$T/invalid.log" 2>&1
rc=$?
set -e
test "$rc" -eq 2
test ! -e "$T/invalid"

printf 'fixture gpu\n' > "$T/staged/usr/libexec/wpe-webkit-2.0/WPEGPUProcess"
FIRE4NIX_WPE_GPU_PROCESS=required FIRE4NIX_WPE_RUNTIME_OUT="$T/with-gpu" \
  sh "$STAGER" --stage > "$T/with-gpu.log"
grep -Fxq 'GPU_PROCESS=required' "$T/with-gpu/GPU-PROFILE.txt"
test -s "$T/with-gpu/libexec/wpe-webkit-2.0/WPEGPUProcess"
(cd "$T/with-gpu" && sha256sum -c SHA256SUMS.txt >/dev/null)

# Launcher must honor the exact manifest, not a generic environment override.
APP="$T/launcher"
mkdir -p "$APP/bin" "$APP/runtime/libexec/wpe-webkit-2.0" "$APP/runtime/lib"
cp "$ROOT/installer/Fire4Nix-Iniciar.sh" "$APP/Fire4Nix-Iniciar.sh"
cat > "$APP/bin/fire4nix-native-aarch64" <<'MOCK'
#!/bin/sh
echo "MOCK-NATIVE-CALLED=$*" >> "$FIRE4NIX_TEST_NATIVE_CALLED"
exit 0
MOCK
chmod +x "$APP/bin/fire4nix-native-aarch64"
cp "$T/no-gpu/lib/libWPEWebKit-2.0.so.1" "$APP/runtime/lib/"
cp "$T/no-gpu/libexec/wpe-webkit-2.0/"* "$APP/runtime/libexec/wpe-webkit-2.0/"
cp "$T/no-gpu/GPU-PROFILE.txt" "$APP/runtime/"
export FIRE4NIX_TEST_NATIVE_CALLED="$T/native-called"
FIRE4NIX_LOG_DIR="$T/launchlogs" sh "$APP/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
grep -Fq 'MOCK-NATIVE-CALLED=' "$T/native-called"
grep -Frq 'gpu_process_profile=disabled' "$T/launchlogs"

# Without the manifest, a package missing GPU helper must fail closed.
rm "$APP/runtime/GPU-PROFILE.txt" "$T/native-called"
set +e
FIRE4NIX_LOG_DIR="$T/launchlogs" sh "$APP/Fire4Nix-Iniciar.sh" --check-platform > "$T/old-mode.log" 2>&1
rc=$?
set -e
test "$rc" -eq 127
test ! -e "$T/native-called"
grep -Fq 'Missing WebKit subprocess: WPEGPUProcess' "$T/old-mode.log"

# Invalid profile must never be treated as GPU-disabled.
echo GPU_PROCESS=sometimes > "$APP/runtime/GPU-PROFILE.txt"
set +e
FIRE4NIX_LOG_DIR="$T/launchlogs" sh "$APP/Fire4Nix-Iniciar.sh" --check-platform > "$T/invalid-profile.log" 2>&1
rc=$?
set -e
test "$rc" -eq 127
grep -Fq 'Invalid runtime GPU profile' "$T/invalid-profile.log"
test ! -e "$T/native-called"
echo 'PASS: GPU-disabled WPE runtime stages/launches only with explicit profile (mock-only)'
