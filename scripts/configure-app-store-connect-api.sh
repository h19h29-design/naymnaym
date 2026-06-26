#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

ASC_DIR=".asc"
ENV_FILE="$ASC_DIR/app-store-connect.env"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

prompt_required() {
  label="$1"
  value=""
  while [ -z "$value" ]; do
    printf '%s: ' "$label" >&2
    IFS= read -r value
  done
  printf '%s\n' "$value"
}

quote_sh() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

mkdir -p "$ASC_DIR"
chmod 700 "$ASC_DIR"

printf 'App Store Connect API local setup\n'
printf 'This stores credentials only under %s, which is gitignored.\n\n' "$ASC_DIR"

KEY_ID="$(prompt_required 'ASC_KEY_ID')"
ISSUER_ID="$(prompt_required 'ASC_ISSUER_ID')"

printf 'Path to downloaded AuthKey_%s.p8, or leave empty to paste PEM content: ' "$KEY_ID" >&2
IFS= read -r SOURCE_KEY_PATH

PRIVATE_KEY_PATH="$ASC_DIR/AuthKey_$KEY_ID.p8"

if [ -n "$SOURCE_KEY_PATH" ]; then
  [ -f "$SOURCE_KEY_PATH" ] || fail "private key file not found: $SOURCE_KEY_PATH"
  cp "$SOURCE_KEY_PATH" "$PRIVATE_KEY_PATH"
else
  printf '\nPaste the .p8 PEM content. Finish with a single line containing only END_ASC_PRIVATE_KEY.\n' >&2
  : >"$PRIVATE_KEY_PATH"
  while IFS= read -r line; do
    [ "$line" = "END_ASC_PRIVATE_KEY" ] && break
    printf '%s\n' "$line" >>"$PRIVATE_KEY_PATH"
  done
fi

chmod 600 "$PRIVATE_KEY_PATH"

grep -q -- 'BEGIN PRIVATE KEY' "$PRIVATE_KEY_PATH" || fail "private key file does not look like a .p8 private key"
grep -q -- 'END PRIVATE KEY' "$PRIVATE_KEY_PATH" || fail "private key file is missing END PRIVATE KEY marker"

cat >"$ENV_FILE" <<EOF
ASC_BUNDLE_ID=com.h19h29.naymnaymlevelup
ASC_VERSION=1.0
ASC_BUILD=16
ASC_KEY_ID=$(quote_sh "$KEY_ID")
ASC_ISSUER_ID=$(quote_sh "$ISSUER_ID")
ASC_PRIVATE_KEY_PATH=$(quote_sh "$ROOT_DIR/$PRIVATE_KEY_PATH")
ASC_REQUIRE_BETA_GROUPS=0
ASC_EXPECTED_BETA_GROUP_NAME=
EOF

chmod 600 "$ENV_FILE"

printf '\nSaved App Store Connect API config to %s\n' "$ENV_FILE"
printf 'Run: scripts/check-app-store-build-status.sh\n'
