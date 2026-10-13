#!/usr/bin/env bash
set -euo pipefail

PKG_CONFIG_BIN="${PKG_CONFIG:-pkg-config}"
MODE="${1:---strict}"

if [[ "$MODE" != "--strict" && "$MODE" != "--report" ]]; then
  echo "Usage: $0 [--strict|--report]" >&2
  exit 2
fi
if ! command -v "$PKG_CONFIG_BIN" >/dev/null 2>&1; then
  echo "[error] pkg-config not found" >&2
  exit 1
fi

missing=0
for name in sdl2 SDL2_image SDL2_ttf SDL2_mixer SDL2_net libcurl; do
  if "$PKG_CONFIG_BIN" --exists "$name"; then
    echo "[ok] $name ($("$PKG_CONFIG_BIN" --modversion "$name"))"
  else
    echo "[missing] $name" >&2
    missing=$((missing + 1))
  fi
done

echo "[info] arch=$(uname -m)"
if (( missing > 0 )); then
  echo "[error] $missing required packages missing" >&2
  if [[ "$MODE" == "--strict" ]]; then exit 1; fi
fi
echo "[info] mode=$MODE"
