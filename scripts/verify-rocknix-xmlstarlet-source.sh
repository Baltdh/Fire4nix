#!/usr/bin/env bash
# Inspect original xmlstarlet 1.6.1 sources without modifying ROCKNIX or R36H.
set -euo pipefail
expected=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
report=${FIRE4NIX_XMLSTARLET_REPORT:-$tmp/xmlstarlet-mirror.txt}
mkdir -p "$(dirname "$report")"
urls=(
 'https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz'
 'https://sourceforge.net/projects/xmlstar/files/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz/download'
)
for url in "${urls[@]}"; do
  if curl --fail --location --silent --show-error --retry 1 --max-time 75 \
       --proto '=https' --tlsv1.2 "$url" -o "$tmp/source.tar.gz"; then
    actual=$(sha256sum "$tmp/source.tar.gz" | cut -d ' ' -f1)
    if [ "$actual" = "$expected" ]; then
      tar -tzf "$tmp/source.tar.gz" > "$tmp/list"
      test -s "$tmp/list"
      {
        echo "MIRROR_VERIFIED=$url"
        echo "VERIFIED_SHA256=$actual"
        echo 'SOURCE_STATUS=PASS'
        echo 'ROCKNIX_TOOLCHAIN_BUILT=no'
      } | tee "$report"
      exit 0
    fi
    echo "HASH_MISMATCH=$actual" >> "$report"
    echo 'ERROR: refusing mismatched archive' >&2
    exit 6
  fi
done
echo 'SOURCE_STATUS=BLOCKED_NO_TRUSTED_MIRROR' | tee -a "$report"
exit 7
