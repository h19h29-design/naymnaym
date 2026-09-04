#!/bin/sh
set -eu

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

require_plist_value() {
  file="$1"
  key="$2"
  expected="$3"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [ "$value" = "$expected" ] || fail "$file $key is '$value', expected '$expected'"
  pass "$file $key is $expected"
}

[ "$#" -eq 2 ] || fail "Usage: $0 APP_DIRECTORY CONFIGURATION"

app_dir="$1"
configuration="$2"
expected_marketing_version="${EXPECTED_MARKETING_VERSION:-1.2}"
expected_build_number="${EXPECTED_BUILD_NUMBER:-34}"

case "$configuration" in
  Debug) expected_platform="iphonesimulator" ;;
  Release) expected_platform="iphoneos" ;;
  *) fail "Unsupported local app configuration: $configuration" ;;
esac

require_file "$app_dir/Info.plist"
require_plist_value "$app_dir/Info.plist" "CFBundleIdentifier" "com.h19h29.naymnaymlevelup"
require_plist_value "$app_dir/Info.plist" "CFBundleShortVersionString" "$expected_marketing_version"
require_plist_value "$app_dir/Info.plist" "CFBundleVersion" "$expected_build_number"
require_plist_value "$app_dir/Info.plist" "CFBundleDisplayName" "급식레벨업"
require_plist_value "$app_dir/Info.plist" "DTPlatformName" "$expected_platform"
pass "$configuration app matches the expected candidate"
