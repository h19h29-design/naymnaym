#!/bin/sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 \
  || fail "Python 3 is required for the App Store screenshot manifest check"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/check-app-store-screenshot-manifest.py" "$@"
