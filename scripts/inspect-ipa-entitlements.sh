#!/bin/sh
set -eu

EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.h19h29.naymnaymlevelup}"
EXPECTED_VERSION="${EXPECTED_VERSION:-1.0}"
EXPECTED_ICLOUD_CONTAINER="${EXPECTED_ICLOUD_CONTAINER:-iCloud.com.h19h29.naymnaymlevelup}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

read_plist() {
  file="$1"
  key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true
}

read_plist_first_or_scalar() {
  file="$1"
  key="$2"
  value="$(read_plist "$file" "${key}:0")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  read_plist "$file" "$key"
}

require_value() {
  value="$1"
  expected="$2"
  description="$3"
  [ "$value" = "$expected" ] || fail "$description is '${value:-missing}', expected '$expected'"
  pass "$description is $expected"
}

require_one_of() {
  value="$1"
  description="$2"
  shift 2

  expected_values=""
  for expected in "$@"; do
    expected_values="${expected_values}${expected_values:+, }$expected"
    if [ "$value" = "$expected" ]; then
      pass "$description is $expected"
      return
    fi
  done

  fail "$description is '${value:-missing}', expected one of: $expected_values"
}

[ "$#" -eq 1 ] || fail "Usage: $0 path/to/NaymNaymLevelUp.ipa"
ipa="$1"
[ -f "$ipa" ] || fail "Missing IPA: $ipa"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

unzip -q "$ipa" -d "$tmp_dir"
app_dir="$(find "$tmp_dir/Payload" -maxdepth 1 -type d -name '*.app' | head -n 1)"
[ -n "$app_dir" ] || fail "$ipa does not contain an app bundle"

info_plist="$app_dir/Info.plist"
bundle_id="$(read_plist "$info_plist" "CFBundleIdentifier")"
version="$(read_plist "$info_plist" "CFBundleShortVersionString")"
build="$(read_plist "$info_plist" "CFBundleVersion")"

require_value "$bundle_id" "$EXPECTED_BUNDLE_ID" "bundle identifier"
require_value "$version" "$EXPECTED_VERSION" "marketing version"
pass "build number is $build"

embedded_profile="$app_dir/embedded.mobileprovision"
[ -f "$embedded_profile" ] || fail "$ipa has no embedded.mobileprovision"
embedded_profile_plist="$tmp_dir/embedded-profile.plist"
security cms -D -i "$embedded_profile" >"$embedded_profile_plist" 2>/dev/null || fail "embedded provisioning profile could not be decoded"

profile_container="$(read_plist_first_or_scalar "$embedded_profile_plist" "Entitlements:com.apple.developer.icloud-container-identifiers")"
profile_service="$(read_plist_first_or_scalar "$embedded_profile_plist" "Entitlements:com.apple.developer.icloud-services")"
profile_aps="$(read_plist_first_or_scalar "$embedded_profile_plist" "Entitlements:aps-environment")"
require_value "$profile_container" "$EXPECTED_ICLOUD_CONTAINER" "embedded profile iCloud container entitlement"
require_one_of "$profile_service" "embedded profile CloudKit service entitlement" "CloudKit" "*"
require_value "$profile_aps" "production" "embedded profile APS entitlement"

signed_entitlements="$tmp_dir/signed-entitlements.plist"
codesign -d --entitlements :- "$app_dir" >"$signed_entitlements" 2>/dev/null || fail "signed app entitlements could not be read"
[ -s "$signed_entitlements" ] || fail "signed app entitlements are empty"

signed_container="$(read_plist_first_or_scalar "$signed_entitlements" "com.apple.developer.icloud-container-identifiers")"
signed_service="$(read_plist_first_or_scalar "$signed_entitlements" "com.apple.developer.icloud-services")"
signed_aps="$(read_plist_first_or_scalar "$signed_entitlements" "aps-environment")"
require_value "$signed_container" "$EXPECTED_ICLOUD_CONTAINER" "signed app iCloud container entitlement"
require_value "$signed_service" "CloudKit" "signed app CloudKit service entitlement"
require_value "$signed_aps" "production" "signed app APS entitlement"

pass "$ipa has release-ready CloudKit and APS entitlements"
