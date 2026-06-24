#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

require_file() {
  [ -f "$1" ] || fail "Missing required file: $1"
  pass "Found $1"
}

check_screenshot() {
  file="$1"
  require_file "$file"

  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')"
  height="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')"
  alpha="$(sips -g hasAlpha "$file" 2>/dev/null | awk '/hasAlpha:/ { print $2 }')"

  [ "$width" = "1320" ] || fail "$file width is $width, expected 1320"
  [ "$height" = "2868" ] || fail "$file height is $height, expected 2868"
  [ "$alpha" = "no" ] || fail "$file has alpha channel"
  pass "$file is 1320x2868 with no alpha"
}

check_url() {
  url="$1"
  status="$(curl -L -s -o /dev/null -w '%{http_code}' "$url")"
  [ "$status" = "200" ] || fail "$url returned HTTP $status"
  pass "$url returned HTTP 200"
}

git diff --check
pass "git diff --check"

require_file "NaymNaymLevelUp/App/Info.plist"
require_file "NaymNaymLevelUp/PrivacyInfo.xcprivacy"
require_file "NaymNaymLevelUp/NaymNaymLevelUp.entitlements"
require_file "Config.example.xcconfig"

git check-ignore -q Config.xcconfig || fail "Config.xcconfig must stay ignored"
pass "Config.xcconfig is ignored"

plutil -lint \
  "NaymNaymLevelUp/App/Info.plist" \
  "NaymNaymLevelUp/PrivacyInfo.xcprivacy" \
  "NaymNaymLevelUp/NaymNaymLevelUp.entitlements" >/dev/null
pass "plist files lint"

for screenshot in docs/app-store-screenshots/iphone-6-9-upload/*.jpg; do
  check_screenshot "$screenshot"
done

count="$(find docs/app-store-screenshots/iphone-6-9-upload -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')"
[ "$count" -ge "1" ] || fail "At least one App Store screenshot is required"
[ "$count" -le "10" ] || fail "App Store screenshot count is $count, expected at most 10"
pass "App Store screenshot count is $count"

for url in \
  "https://h19h29-design.github.io/naymnaym/" \
  "https://h19h29-design.github.io/naymnaym/privacy.html" \
  "https://h19h29-design.github.io/naymnaym/support.html" \
  "https://h19h29-design.github.io/naymnaym/data-safety.html"
do
  check_url "$url"
done

pass "release readiness checks completed"
