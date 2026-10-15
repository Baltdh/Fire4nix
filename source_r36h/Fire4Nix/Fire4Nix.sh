#!/bin/sh
set -eu
APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec bash "$APP_DIR/scripts/run_browser.sh" "$@"
