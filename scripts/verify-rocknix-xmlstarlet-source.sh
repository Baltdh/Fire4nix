#!/usr/bin/env bash
# Source-only, fail-closed ROCKNIX 20260801 xmlstarlet-1.6.1 verification.
# Never install a host package or alter the firmware, device, or pinned digest.
set -euo pipefail
case "${1:---check}" in --check) ;; --help)
  echo 'Usage: FIRE4NIX_XMLSTARLET_REPORT=/tmp/report.txt bash verify-rocknix-xmlstarlet-source.sh --check'; exit 0 ;;
  *) echo 'ERROR: --check only' >&2; exit 2 ;;
esac
for program in curl tar sha256sum awk mktemp; do
  command -v "$program" >/dev/null || { echo "ERROR: $program unavailable" >&2; exit 4; }
done
readonly EXPECTED_SHA=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca
readonly EXPECTED_SIZE=420923
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
report=${FIRE4NIX_XMLSTARLET_REPORT:-"$work/verification.txt"}
mkdir -p "$(dirname -- "$report")"
{
  echo 'SOURCE_PACKAGE=xmlstarlet'
  echo 'SOURCE_VERSION=1.6.1'
  echo "SOURCE_REQUIRED_SHA256=$EXPECTED_SHA"
  echo 'ROCKNIX_SOURCE_RELEASE=20260801'
  echo 'TOOLCHAIN_BUILT=no'
  echo 'SOURCE_RECIPE_CHANGED=no'
} > "$report"
urls=(
  'https://sources.libreelec.tv/mirror/xmlstarlet/xmlstarlet-1.6.1.tar.gz'
  'https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz'
  'https://sourceforge.net/projects/xmlstar/files/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz/download'
)
for url in "${urls[@]}"; do
  echo "CHECKING_SOURCE=$url"
  if curl --fail --location --silent --show-error \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout 10 --max-time 40 --max-filesize 1048576 \
      --retry 0 --output "$work/archive.tar.gz" "$url"; then
    size=$(wc -c < "$work/archive.tar.gz" | tr -d ' ')
    sha=$(sha256sum "$work/archive.tar.gz" | awk '{print $1}')
    if [[ "$sha" == "$EXPECTED_SHA" && "$size" == "$EXPECTED_SIZE" ]] &&
        tar -tzf "$work/archive.tar.gz" > "$work/listing.txt" &&
        grep -Fxq 'xmlstarlet-1.6.1/configure' "$work/listing.txt" &&
        grep -Fxq 'xmlstarlet-1.6.1/src/xml.c' "$work/listing.txt"; then
      {
        echo 'XMLSTARLET_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256'
        echo "VERIFIED_URL=$url"
        echo "VERIFIED_SHA256=$sha"
        echo "VERIFIED_SIZE=$size"
      } >> "$report"
      cat "$report"
      exit 0
    fi
    echo "SOURCE_REJECTED=$url size=$size sha256=$sha" >> "$report"
  else
    echo "SOURCE_UNAVAILABLE=$url" >> "$report"
  fi
done
echo 'XMLSTARLET_SOURCE_STATUS=BLOCKED_NO_AUTHENTIC_TARBALL' >> "$report"
cat "$report"
exit 7
