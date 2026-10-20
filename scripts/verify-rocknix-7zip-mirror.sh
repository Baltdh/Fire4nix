#!/usr/bin/env bash
# FIRE4NIX: public source mirror and checksum diagnostic for ROCKNIX 20260801 7-zip.
# Does not build/extract/execute archives or modify original ROCKNIX files.
set -euo pipefail
EXPECTED_VERSION=25.00
EXPECTED_SHA256=bff9e69b6ca73a5b8715d7623870a39dc90ad6ce1f4d1070685843987af1af9b
expected_filename=7z2500-src.tar.xz
mode=${1:---check}
case "$mode" in --check|--help) ;; *) echo 'Usage: bash verify-rocknix-7zip-mirror.sh --check' >&2; exit 2 ;; esac
[ "$mode" != --help ] || { echo 'Checks official ROCKNIX 20260801 7-zip 25.00 tar.xz mirror and SHA256'; exit 0; }
for cmd in curl sha256sum tar mktemp; do command -v "$cmd" >/dev/null || exit 4; done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
report=${FIRE4NIX_7ZIP_REPORT:-$tmp/rocknix-7zip-source.txt}
mkdir -p "$(dirname "$report")"
{
  echo 'ROCKNIX_RELEASE=20260801'
  echo "7ZIP_VERSION=$EXPECTED_VERSION"
  echo "EXPECTED_SHA256=$EXPECTED_SHA256"
  echo 'BROWSER_COMPILED=no'
  echo 'TOOLCHAIN_COMPILED=no'
  echo 'DEVICE_MODIFIED=no'
} > "$report"
urls=(
  'https://downloads.sourceforge.net/project/sevenzip/7-Zip/25.00/7z2500-src.tar.xz'
  'https://sourceforge.net/projects/sevenzip/files/7-Zip/25.00/7z2500-src.tar.xz/download'
  'https://master.dl.sourceforge.net/project/sevenzip/7-Zip/25.00/7z2500-src.tar.xz'
)
for i in "${!urls[@]}"; do
  url=${urls[$i]}
  printf 'Trying 7-Zip 25.00 mirror %d of %d\n' "$((i+1))" "${#urls[@]}"
  : > "$tmp/headers"
  if curl --fail --location --show-error --silent --retry 1 --max-time 75 \
       --proto '=https' --tlsv1.2 \
       --dump-header "$tmp/headers" --output "$tmp/$expected_filename" "$url"; then
    actual=$(sha256sum "$tmp/$expected_filename" | cut -d ' ' -f1)
    bytes=$(wc -c < "$tmp/$expected_filename")
    echo "MIRROR_$((i+1))_HTTP=DOWNLOADED bytes=$bytes sha256=$actual" >> "$report"
    if [ "$actual" != "$EXPECTED_SHA256" ]; then
      echo "MIRROR_$((i+1))_STATUS=HASH_MISMATCH" >> "$report"
      echo 'ERROR: source digest mismatch, archive not trusted' >&2
      exit 5
    fi
    if ! tar -tJf "$tmp/$expected_filename" > "$tmp/archive-list"; then
      echo 'ERROR: source digest matched but archive tar.xz listing failed' >&2
      exit 6
    fi
    test -s "$tmp/archive-list" || { echo 'ERROR: empty source archive' >&2; exit 6; }
    {
      echo "MIRROR_VERIFIED=$url"
      echo "VERIFIED_FILENAME=$expected_filename"
      echo "VERIFIED_SHA256=$actual"
      echo 'SOURCE_MIRROR_STATUS=PASS'
      echo 'NOT_INSTALLED_OR_BUILT=yes'
    } >> "$report"
    cat "$report"
    exit 0
  else
    echo "MIRROR_$((i+1))_STATUS=HTTP_OR_NETWORK_FAILED" >> "$report"
  fi
done
echo 'SOURCE_MIRROR_STATUS=BLOCKED_ALL_MIRRORS' >> "$report"
cat "$report"
exit 7
