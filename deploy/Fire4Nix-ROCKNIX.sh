#!/bin/sh
# Fire4Nix ROCKNIX portable launcher: works from Ports, Tools, Downloads,
# external storage, or any readable directory containing the app.
set -u

resolve_launcher_dir() {
  target=$1
  case "$target" in
    /*) ;;
    *) target="$(pwd)/$target" ;;
  esac
  hops=0
  while [ -L "$target" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 20 ] || return 1
    link=$(readlink "$target") || return 1
    case "$link" in
      /*) target=$link ;;
      *) target="$(dirname "$target")/$link" ;;
    esac
  done
  CDPATH="" cd -- "$(dirname "$target")" && pwd -P
}

find_app() {
  # Explicit override takes precedence, but only if it is valid.
  if [ -n "${FIRE4NIX_APP_DIR:-}" ]; then
    [ -f "$FIRE4NIX_APP_DIR/Fire4Nix.sh" ] || return 1
    printf '%s\n' "$FIRE4NIX_APP_DIR"
    return 0
  fi

  script_dir=$(resolve_launcher_dir "$0") || return 1
  for candidate in \
    "$script_dir/Fire4Nix" \
    "$script_dir/navegador-definitivo" \
    "$script_dir/../Fire4Nix" \
    "$script_dir/../navegador-definitivo" \
    /storage/games-internal/roms/tools/Fire4Nix \
    /storage/games-internal/roms/tools/navegador-definitivo \
    /storage/games-external/roms/tools/Fire4Nix \
    /storage/roms/ports/Fire4Nix \
    /storage/roms/ports/fire4nix \
    /storage/roms/ports/Fire4nix \
    /storage/roms/ports/navegador-definitivo \
    /storage/roms/tools/Fire4Nix \
    "$script_dir"; do
    # If this launcher was named Fire4Nix.sh in the Tools directory,
    # don't re-enter the same file as if it were the browser application.
    if [ "$candidate" = "$script_dir" ] && [ "$(basename -- "$0")" = "Fire4Nix.sh" ]; then
      continue
    fi
    if [ -f "$candidate/Fire4Nix.sh" ]; then
      (CDPATH="" cd -- "$candidate" && pwd -P)
      return $?
    fi
  done
  return 1
}

LOG="${FIRE4NIX_LAUNCH_LOG:-/storage/fire4nix-launch.log}"
if [ -z "${FIRE4NIX_LAUNCH_LOG:-}" ] && { [ ! -d /storage ] || [ ! -w /storage ]; }; then
  LOG="${TMPDIR:-/tmp}/fire4nix-launch.log"
fi
APP=$(find_app) || APP=""
(
  echo "=== Fire4Nix $(date) ==="
  echo "arch=$(uname -m) uid=$(id -u) app=$APP"
  if [ -z "$APP" ] || [ ! -f "$APP/Fire4Nix.sh" ]; then
    echo "ERROR: Fire4Nix application was not found in Tools."
    echo "Expected a sibling folder named Fire4Nix containing Fire4Nix.sh."
    echo "Detected Tools path: $(resolve_launcher_dir "$0" 2>/dev/null || echo unknown)"
    exit 3
  fi
  if [ "$(basename -- "$0")" = "Fire4Nix.sh" ] && [ "$APP/Fire4Nix.sh" = "$(resolve_launcher_dir "$0" 2>/dev/null)/Fire4Nix.sh" ]; then
    echo "ERROR: recursive launcher path detected; refusing to call the same Tools script."
    exit 3
  fi
  if ! command -v bash >/dev/null 2>&1; then
    echo "ERROR: bash unavailable"
    exit 127
  fi
  DATA_ROOT="${FIRE4NIX_DATA_ROOT:-/storage}"
  [ -d "$DATA_ROOT" ] && [ -w "$DATA_ROOT" ] || DATA_ROOT="${HOME:-/tmp}"
  export FIRE4NIX_CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$DATA_ROOT/.config/fire4nix}"
  export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$DATA_ROOT/.cache/fire4nix/runtime}"
  export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$DATA_ROOT/.cache/fire4nix/logs}"
  mkdir -p "$FIRE4NIX_CONFIG_DIR" "$FIRE4NIX_RUNTIME_DIR" "$FIRE4NIX_LOG_DIR" || exit 4
  cd "$APP" || exit 5
  bash "$APP/Fire4Nix.sh" "$@"
  rc=$?
  echo "Browser exit code: $rc"
  exit "$rc"
) >>"$LOG" 2>&1
exit $?
