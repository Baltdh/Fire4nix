#!/usr/bin/env bash
# Verify exact GNU configtools source for pinned ROCKNIX 20260801; no build, no firmware writes.
set -euo pipefail
COMMIT=28ea239c53a2d5d8800c472bc2452eaa16e37af2
EXPECTED_SHA=6e4ebaa2a60114cf8b72d478b30e559f0c8e025d290ae3303773095104bf7bcc
MODE=${1:---check}
case "$MODE" in --check|--help) ;; *) echo "Usage: --check|--help" >&2; exit 2;; esac
[[ "$MODE" == --help ]] && { echo "Identify and verify GNU configtools 2023 revision archive"; exit 0; }
for cmd in curl sha256sum tar git timeout; do command -v "$cmd" >/dev/null || exit 4; done
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
REPORT=${FIRE4NIX_CONFIGTOOLS_REPORT:-"$WORK/report.txt"}
mkdir -p "$(dirname "$REPORT")"
{ echo "REQUIRED_GNU_CONFIG_COMMIT=$COMMIT"; echo "REQUIRED_ROCKNIX_TARBALL_SHA256=$EXPECTED_SHA"; echo "TOOLCHAIN_BUILT=no"; echo "WEBKIT_BUILT=no"; } > "$REPORT"
urls=(
  "https://cgit.git.savannah.gnu.org/cgit/config.git/snapshot/config-$COMMIT.tar.gz"
  "https://git.savannah.gnu.org/cgit/config.git/snapshot/config-$COMMIT.tar.gz"
  "https://sources.libreelec.tv/mirror/configtools/configtools-$COMMIT.tar.gz"
)
for url in "${urls[@]}"; do
  echo "VERIFYING_SOURCE_URL=$url"
  if curl -L -f -sS --proto "=https" --max-time 35 --connect-timeout 10 --retry 0 -o "$WORK/config.tar.gz" "$url"; then
    digest=$(sha256sum "$WORK/config.tar.gz" | cut -d " " -f1)
    if [[ "$digest" == "$EXPECTED_SHA" ]] && tar -tzf "$WORK/config.tar.gz" > "$WORK/archive-list.txt" && grep -Eq "(^|/)config\.guess$" "$WORK/archive-list.txt"; then
      echo "CONFIGTOOLS_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256" >> "$REPORT"
      echo "VERIFIED_URL=$url" >> "$REPORT"
      cat "$REPORT"
      exit 0
    fi
    echo "SOURCE_CHECKSUM_MISMATCH=$url got=$digest" >> "$REPORT"
  else
    echo "SOURCE_UNAVAILABLE=$url" >> "$REPORT"
  fi
done
# GNU Savannah maintainers recommend git clone + git archive when cgit snapshots are disabled.
# This route proves COMMIT identity, not binary equivalence with the legacy snapshot tarball.
git_url=https://git.savannah.gnu.org/git/config.git
if timeout 120s git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=20 clone -q "$git_url" "$WORK/config-git"; then
  if git -C "$WORK/config-git" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
    actual=$(git -C "$WORK/config-git" rev-parse "$COMMIT^{commit}")
    [[ "$actual" == "$COMMIT" ]] || { echo "ERROR: upstream commit identity mismatch" >&2; exit 6; }
    git -C "$WORK/config-git" archive --format=tar.gz --prefix="config-$COMMIT/" "$COMMIT" > "$WORK/reconstructed.tar.gz"
    digest=$(sha256sum "$WORK/reconstructed.tar.gz" | cut -d " " -f1)
    tar -tzf "$WORK/reconstructed.tar.gz" > "$WORK/reconstructed-list.txt" || exit 6
    grep -Fxq "config-$COMMIT/config.guess" "$WORK/reconstructed-list.txt" || exit 6
    grep -Fxq "config-$COMMIT/config.sub" "$WORK/reconstructed-list.txt" || exit 6
    echo "UPSTREAM_COMMIT_VERIFIED=$actual" >> "$REPORT"
    echo "RECONSTRUCTED_ARCHIVE_SHA256=$digest" >> "$REPORT"
    if [[ "$digest" == "$EXPECTED_SHA" ]]; then
      echo "CONFIGTOOLS_SOURCE_STATUS=PASS_RECONSTRUCTED_ROCKNIX_SHA256" >> "$REPORT"
      cat "$REPORT"
      exit 0
    fi
    echo "CONFIGTOOLS_SOURCE_STATUS=SOURCE_COMMIT_VERIFIED_ARCHIVE_HASH_DIFFERS" >> "$REPORT"
    echo "NEXT_ACTION=REVIEW_REPRODUCIBLE_ARCHIVE_PIN_NO_AUTOMATIC_SHA_CHANGE" >> "$REPORT"
    cat "$REPORT"
    exit 8
  fi
  echo "GIT_COMMIT_NOT_PRESENT=$COMMIT" >> "$REPORT"
else
  echo "GIT_REPOSITORY_UNAVAILABLE=$git_url" >> "$REPORT"
fi
echo "CONFIGTOOLS_SOURCE_STATUS=BLOCKED" >> "$REPORT"
cat "$REPORT"
exit 7
