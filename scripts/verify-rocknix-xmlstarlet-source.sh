#!/usr/bin/env bash
# Verify the *exact* xmlstarlet 1.6.1 source requested by ROCKNIX 20260801.
# Read/download on build host only. No changes to package hashes or R36H.
set -euo pipefail
mode=\${1:---check}
case "$mode" in --check) ;; --help)
  echo 'FIRE4NIX_XMLSTARLET_REPORT=/absolute/report.txt bash scripts/verify-rocknix-xmlstarlet-source.sh --check'; exit 0;;
  *) echo 'ERROR: use --check or --help' >&2; exit 2;;
esac
version=1.6.1
expected=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca
for cmd in curl sha256sum tar mktemp grep; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd required" >&2; exit 4; }
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
report=\${FIRE4NIX_XMLSTARLET_REPORT:-"$work/source-report.txt"}
mkdir -p "$(dirname "$report")"
{
  echo "PACKAGE=xmlstarlet"
  echo "REQUIRED_VERSION=$version"
  echo "REQUIRED_ROCKNIX_SHA256=$expected"
  echo 'TOOLCHAIN_BUILT=no'
  echo 'R36H_MODIFIED=no'
} > "$report"
urls=(
  'https://sources.libreelec.tv/mirror/xmlstarlet/xmlstarlet-1.6.1.tar.gz'
  'https://deb.debian.org/debian/pool/main/x/xmlstarlet/xmlstarlet_1.6.1.orig.tar.gz'
  'https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz'
)
for url in "\${urls[@]}"; do
  echo "CHECKING_URL=$url"
  archive="$work/xmlstarlet-1.6.1.tar.gz"
  rm -f "$archive"
  if ! curl --proto '=https' --proto-redir '=https' -fsSL \
       --connect-timeout 10 --max-time 40 --retry 1 \
       --output "$archive" "$url"; then
    echo "SOURCE_UNAVAILABLE=$url" >> "$report"
    continue
  fi
  actual=$(sha256sum "$archive" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "SOURCE_CHECKSUM_MISMATCH=$url got=$actual" >> "$report"
    continue
  fi
  if ! tar -tzf "$archive" > "$work/entries.txt" ||
     ! grep -Fxq "xmlstarlet-$version/configure" "$work/entries.txt"; then
    echo "SOURCE_ARCHIVE_LAYOUT_INVALID=$url" >> "$report"
    continue
  fi
  echo 'XMLSTARLET_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256' >> "$report"
  echo "VERIFIED_URL=$url" >> "$report"
  echo "VERIFIED_SHA256=$actual" >> "$report"
  echo "VERIFIED_BYTES=$(wc -c < "$archive" | tr -d ' ')" >> "$report"
  cat "$report"
  exit 0
done
echo 'XMLSTARLET_SOURCE_STATUS=BLOCKED_NO_MATCHING_SOURCE' >> "$report"
cat "$report"
exit 7
