#!/bin/sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

[ "${RELEASE_UPLOAD_REQUIRED:-}" = "0" ] \
  || fail "check-release-upload-disabled.sh requires RELEASE_UPLOAD_REQUIRED=0"
pass "Signed archive, export IPA, and upload-log checks skipped because RELEASE_UPLOAD_REQUIRED=0"
