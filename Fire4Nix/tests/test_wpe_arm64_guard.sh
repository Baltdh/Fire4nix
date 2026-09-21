#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_SCRIPT="$APP_DIR/scripts/build_wpe_arm64.sh"

fail() { printf 'build_wpe_arm64 guard test: FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$BUILD_SCRIPT" ] || fail "missing build script"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"

cat > "$TMP/bin/pkg-config" <<'EOF'
#!/bin/sh
case "$1" in
  --exists) exit 0 ;;
  --modversion) echo 2.52.5 ;;
  --cflags|--libs) exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/pkg-config"

cat > "$TMP/bin/fake-g++" <<'EOF'
#!/bin/sh
if [ "$1" = "-dumpmachine" ]; then
  echo x86_64-linux-gnu
  exit 0
fi
exit 99
EOF
chmod +x "$TMP/bin/fake-g++"

set +e
PATH="$TMP/bin:$PATH" PKG_CONFIG=pkg-config CXX=fake-g++ sh "$BUILD_SCRIPT" >"$TMP/out" 2>&1
rc=$?
set -e

cat "$TMP/out"
[ "$rc" -eq 2 ] || fail "expected architecture guard exit 2, got $rc"
grep -q "not ARM64/aarch64" "$TMP/out" || fail "architecture rejection message missing"

printf 'build_wpe_arm64 guard test: PASS\n'
