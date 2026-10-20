#!/bin/sh
# Fire4Nix: verify upstream sources of absent WPE prerequisites.
# --list = static manifest only; --download downloads to ephemeral CI /tmp and checks SHA256.
# Never installs libraries, touches firmware/SD or pretends a WPE browser was built.
set -eu
mode=${1:---list}
case "$mode" in
  --list|--download) ;;
  --help) echo 'sh verify-wpe-prerequisite-sources.sh [--list|--download]'; exit 0 ;;
  *) echo 'ERROR: supported options --list, --download' >&2; exit 2 ;;
esac
self=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
lock=${FIRE4NIX_DEPENDENCY_LOCK:-"$self/rocknix-wpe-prerequisites.lock"}
[ -r "$lock" ] || { echo 'ERROR: dependency lock missing' >&2; exit 4; }
temp=''
cleanup() { [ -z "$temp" ] || rm -rf "$temp"; }
trap cleanup EXIT
if [ "$mode" = --download ]; then
  command -v curl >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 ||
    { echo 'ERROR: curl and sha256sum required' >&2; exit 4; }
  temp=$(mktemp -d) || exit 4
fi
count=0
while IFS='|' read -r name digest url || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue ;; esac
  case "$name" in libsoup3|libtasn1|glib-networking|libpsl) ;; *)
    echo "ERROR: unsupported or unreviewed dependency: $name" >&2; exit 4 ;;
  esac
  if ! printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "ERROR: malformed SHA256 for $name" >&2; exit 4
  fi
  case "$url" in https://*) ;; *) echo "ERROR: non-HTTPS source for $name" >&2; exit 4 ;; esac
  echo "LOCKED_SOURCE=$name"
  count=$((count + 1))
  if [ "$mode" = --download ]; then
    archive="$temp/$name.source"
    curl --fail --location --retry 3 --retry-delay 3 --proto '=https' --tlsv1.2 \
      --silent --show-error "$url" --output "$archive"
    printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status ||
      { echo "ERROR: source digest mismatched for $name" >&2; exit 5; }
    echo "SOURCE_OK=$name"
  fi
done < "$lock"
[ "$count" -eq 4 ] || { echo "ERROR: expected 4 missing-package source locks, got $count" >&2; exit 4; }
if [ "$mode" = --download ]; then
  echo 'PREREQUISITE_SOURCE_CHECK=4_ARCHIVES_SHA256_VERIFIED'
else
  echo 'PREREQUISITE_SOURCE_CHECK=4_LOCKS_VALID_ARCHIVES_NOT_DOWNLOADED'
fi
echo 'SDK_BUILT=no'
echo 'WEBKIT_COMPILED=no'
