#!/bin/sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

[ "$#" -eq 2 ] || fail "Usage: $0 DIRECTORY EXPECTED_FILE_COUNT < manifest"

directory="$1"
expected_count="$2"
[ -d "$directory" ] || fail "Missing App Store screenshot directory: $directory"

jpg_count="$(find "$directory" -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')"
[ "$jpg_count" = "$expected_count" ] || fail "App Store screenshot count is $jpg_count, expected exactly $expected_count"
pass "App Store screenshot count is $jpg_count"

file_count="$(find "$directory" -maxdepth 1 -type f -exec printf x ';' | wc -c | tr -d ' ')"
[ "$file_count" = "$expected_count" ] || fail "App Store screenshot file count is $file_count, expected exactly $expected_count"
pass "App Store screenshot file count is $file_count"

while IFS= read -r manifest_file; do
  [ -n "$manifest_file" ] || continue
  [ -f "$directory/$manifest_file" ] || fail "Missing App Store screenshot file: $directory/$manifest_file"
done
pass "App Store screenshot directory contains only the current manifest"
