#!/bin/sh
# CI mock exercise: does NOT build an actual WebKit or claim Mali support.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/staged/usr/lib" "$T/staged/usr/libexec/wpe-webkit-2.0"
[ -f /tmp/modern-wpe/libWPEWebKit-2.0.so.1 ] || { echo 'Run after the WPE ABI mock build' >&2; exit 2; }
cp /tmp/modern-wpe/libWPEWebKit-2.0.so.1 "$T/staged/usr/lib/"
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  cp "$ROOT/out/Fire4Nix/bin/fire4nix-native-aarch64" "$T/staged/usr/libexec/wpe-webkit-2.0/$p"
done
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/runtime" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/staged.log"
grep -q 'STATUS=ELF_VERIFIED_DEPENDENCIES_AND_REAL_WAYLAND_UNTESTED' "$T/staged.log"
test -s "$T/runtime/lib/libWPEWebKit-2.0.so.1"
test -s "$T/runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
grep -q 'AArch64 ELF and WPEPlatform exported symbol checked' "$T/runtime/BUILD-REPORT.txt"
(cd "$T/runtime" && sha256sum -c SHA256SUMS.txt >/dev/null)
set +e
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/runtime" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/overwrite.log" 2>&1
overwrite=$?
set -e
test "$overwrite" -eq 2
grep -q 'already exists' "$T/overwrite.log"
# An incomplete WPE stage must not create any output.
rm -f "$T/staged/usr/libexec/wpe-webkit-2.0/WPEGPUProcess"
set +e
FIRE4NIX_WPE_DESTDIR="$T/staged" FIRE4NIX_WPE_RUNTIME_OUT="$T/incomplete" \
  sh "$ROOT/rocknix-integration/stage-wpe-runtime.sh" --stage > "$T/missing-child.log" 2>&1
missing=$?
set -e
test "$missing" -eq 3
test ! -e "$T/incomplete"
grep -q 'missing staged WPEGPUProcess' "$T/missing-child.log"
echo 'PASS: WPE staged DESTDIR gets ARM64 ABI/child checks, SHA-256 manifest and no-overwrite protection'
