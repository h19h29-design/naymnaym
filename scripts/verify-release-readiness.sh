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

check_image() {
  file="$1"
  expected_width="$2"
  expected_height="$3"
  require_file "$file"

  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')"
  height="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')"
  alpha="$(sips -g hasAlpha "$file" 2>/dev/null | awk '/hasAlpha:/ { print $2 }')"

  [ "$width" = "$expected_width" ] || fail "$file width is $width, expected $expected_width"
  [ "$height" = "$expected_height" ] || fail "$file height is $height, expected $expected_height"
  [ "$alpha" = "no" ] || fail "$file has alpha channel"
  pass "$file is ${expected_width}x${expected_height} with no alpha"
}

require_plist_value() {
  file="$1"
  key="$2"
  expected="$3"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [ "$value" = "$expected" ] || fail "$file $key is '$value', expected '$expected'"
  pass "$file $key is $expected"
}

require_nonempty_plist_value() {
  file="$1"
  key="$2"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [ -n "$value" ] || fail "$file $key must not be empty"
  pass "$file $key is present"
}

require_pattern() {
  file="$1"
  pattern="$2"
  description="$3"
  grep -Eq "$pattern" "$file" || fail "$description"
  pass "$description"
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

require_plist_value "NaymNaymLevelUp/App/Info.plist" "CFBundleDisplayName" "냠냠레벨업"
require_plist_value "NaymNaymLevelUp/App/Info.plist" "CFBundleIconName" "AppIcon"
require_plist_value "NaymNaymLevelUp/App/Info.plist" "ITSAppUsesNonExemptEncryption" "false"
require_plist_value "NaymNaymLevelUp/App/Info.plist" "LSApplicationCategoryType" "public.app-category.education"
require_plist_value "NaymNaymLevelUp/App/Info.plist" "NEIS_API_KEY" "\$(NEIS_API_KEY)"
require_nonempty_plist_value "NaymNaymLevelUp/App/Info.plist" "NSCameraUsageDescription"
require_nonempty_plist_value "NaymNaymLevelUp/App/Info.plist" "NSPhotoLibraryUsageDescription"
require_nonempty_plist_value "NaymNaymLevelUp/App/Info.plist" "NSPhotoLibraryAddUsageDescription"
require_plist_value "NaymNaymLevelUp/NaymNaymLevelUp.entitlements" "com.apple.developer.icloud-container-identifiers:0" "iCloud.com.h19h29.naymnaymlevelup"
require_plist_value "NaymNaymLevelUp/NaymNaymLevelUp.entitlements" "com.apple.developer.icloud-services:0" "CloudKit"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1\\.0;" "App marketing version is 1.0"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "CURRENT_PROJECT_VERSION = 13;" "App build number is 13"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = \"com\\.h19h29\\.naymnaymlevelup\";" "Bundle ID is com.h19h29.naymnaymlevelup"
require_pattern "docs/APP_STORE_METADATA.md" "^- 버전: 1\\.0$" "App Store metadata version is 1.0"
require_pattern "docs/APP_STORE_METADATA.md" "^- 빌드: 13$" "App Store metadata build is 13"
require_pattern "release/AppStoreMetadata/ko-KR.md" "^- 버전: 1\\.0$" "ko-KR metadata version is 1.0"
require_pattern "release/AppStoreMetadata/ko-KR.md" "^- 빌드: 13$" "ko-KR metadata build is 13"

check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-20@2x.png" 40 40
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-20@3x.png" 60 60
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-29@2x.png" 58 58
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-29@3x.png" 87 87
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-40@2x.png" 80 80
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-40@3x.png" 120 120
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png" 120 120
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png" 180 180
check_image "NaymNaymLevelUp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" 1024 1024

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
