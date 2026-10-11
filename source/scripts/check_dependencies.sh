#!/usr/bin/env bash
set -eu

PKG_CONFIG_BIN="${PKG_CONFIG:-pkg-config}"

if ! command -v "$PKG_CONFIG_BIN" >/dev/null 2>&1; then
  echo "[error] pkg-config not found" >&2
  exit 1
fi

check_pkg() {
  local name="$1"
  if "$PKG_CONFIG_BIN" --exists "$name" >/dev/null 2>&1; then
    echo "[ok] $name"
  else
    echo "[warn] $name missing" >&2
  fi
}

check_pkg sdl2
check_pkg SDL2_image
check_pkg SDL2_ttf
check_pkg SDL2_mixer
check_pkg SDL2_net
check_pkg libcurl

if command -v uname >/dev/null 2>&1; then
  echo "[info] arch=$(uname -m)"
fi
