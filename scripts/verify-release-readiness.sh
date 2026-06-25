#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

RELEASE_BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-15}"
RELEASE_UPLOAD_LOG="${RELEASE_UPLOAD_LOG:-build/build${RELEASE_BUILD_NUMBER}-signed-upload.log}"
RELEASE_EXPORT_DIR="${RELEASE_EXPORT_DIR:-build/TestFlightExportBuild${RELEASE_BUILD_NUMBER}Signed}"
RELEASE_IPA_PATH="${RELEASE_IPA_PATH:-${RELEASE_EXPORT_DIR}/NaymNaymLevelUp.ipa}"

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

require_absent_path() {
  [ ! -e "$1" ] || fail "$1 must not exist for the no-third-party-SDK release profile"
  pass "$1 is absent"
}

require_not_tracked() {
  path="$1"
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    fail "$path must not be tracked by Git"
  fi
  pass "$path is not tracked by Git"
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

require_signed_entitlement() {
  file="$1"
  key="$2"
  expected="$3"
  description="$4"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    case "$key" in
      *:0)
        value="$(/usr/libexec/PlistBuddy -c "Print :${key%:0}" "$file" 2>/dev/null || true)"
        ;;
    esac
  fi
  [ "$value" = "$expected" ] || fail "$description is '${value:-missing}', expected '$expected'"
  pass "$description is $expected"
}

require_signed_entitlement_one_of() {
  file="$1"
  key="$2"
  description="$3"
  shift 3
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    case "$key" in
      *:0)
        value="$(/usr/libexec/PlistBuddy -c "Print :${key%:0}" "$file" 2>/dev/null || true)"
        ;;
    esac
  fi

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

require_nonempty_plist_value() {
  file="$1"
  key="$2"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [ -n "$value" ] || fail "$file $key must not be empty"
  pass "$file $key is present"
}

require_missing_plist_key() {
  file="$1"
  key="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$file" >/dev/null 2>&1; then
    fail "$file $key must not be present"
  fi
  pass "$file $key is absent"
}

require_empty_plist_array() {
  file="$1"
  key="$2"
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [ "$value" = "Array {
}" ] || fail "$file $key must be an empty array"
  pass "$file $key is an empty array"
}

require_pattern() {
  file="$1"
  pattern="$2"
  description="$3"
  grep -Eq "$pattern" "$file" || fail "$description"
  pass "$description"
}

require_absent_pattern() {
  scope="$1"
  pattern="$2"
  description="$3"
  if grep -ERq "$pattern" $scope; then
    fail "$description"
  fi
  pass "$description"
}

check_url() {
  url="$1"
  status="$(curl -L -s -o /dev/null -w '%{http_code}' "$url")"
  [ "$status" = "200" ] || fail "$url returned HTTP $status"
  pass "$url returned HTTP 200"
}

check_uploaded_ipa() {
  ipa="$1"
  expected_build="$2"
  require_file "$ipa"
  require_not_tracked "$ipa"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  unzip -q "$ipa" -d "$tmp_dir"
  app_dir="$(find "$tmp_dir/Payload" -maxdepth 1 -type d -name '*.app' | head -n 1)"
  [ -n "$app_dir" ] || fail "$ipa does not contain an app bundle"

  require_plist_value "$app_dir/Info.plist" "CFBundleIdentifier" "com.h19h29.naymnaymlevelup"
  require_plist_value "$app_dir/Info.plist" "CFBundleShortVersionString" "1.0"
  require_plist_value "$app_dir/Info.plist" "CFBundleVersion" "$expected_build"
  require_plist_value "$app_dir/Info.plist" "CFBundleDisplayName" "냠냠레벨업"

  embedded_profile="$app_dir/embedded.mobileprovision"
  require_file "$embedded_profile"
  embedded_profile_plist="$tmp_dir/embedded-profile.plist"
  security cms -D -i "$embedded_profile" >"$embedded_profile_plist" 2>/dev/null || fail "$ipa embedded provisioning profile could not be decoded"
  require_signed_entitlement "$embedded_profile_plist" "Entitlements:com.apple.developer.icloud-container-identifiers:0" "iCloud.com.h19h29.naymnaymlevelup" "$ipa embedded profile iCloud container entitlement"
  require_signed_entitlement_one_of "$embedded_profile_plist" "Entitlements:com.apple.developer.icloud-services:0" "$ipa embedded profile CloudKit service entitlement" "CloudKit" "*"

  entitlements_file="$tmp_dir/signed-entitlements.plist"
  codesign -d --entitlements :- "$app_dir" >"$entitlements_file" 2>/dev/null || fail "$ipa signed entitlements could not be read"
  [ -s "$entitlements_file" ] || fail "$ipa signed entitlements are empty"
  require_signed_entitlement "$entitlements_file" "com.apple.developer.icloud-container-identifiers:0" "iCloud.com.h19h29.naymnaymlevelup" "$ipa signed iCloud container entitlement"
  require_signed_entitlement "$entitlements_file" "com.apple.developer.icloud-services:0" "CloudKit" "$ipa signed CloudKit service entitlement"

  rm -rf "$tmp_dir"
  pass "$ipa contains build 1.0 ($expected_build)"
}

git diff --check
pass "git diff --check"

require_file "NaymNaymLevelUp/App/Info.plist"
require_file "NaymNaymLevelUp/PrivacyInfo.xcprivacy"
require_file "NaymNaymLevelUp/NaymNaymLevelUp.entitlements"
require_file "Config.example.xcconfig"
require_file "release/AppStoreMetadata/app-store-connect-values.json"
require_file "release/CloudKit/schema-contract.json"
require_file "release/ReleaseStatus/build-15-readiness.json"
require_file "scripts/check-app-store-build-status.sh"
sh -n scripts/check-app-store-build-status.sh
pass "App Store Connect build status script syntax"
require_pattern "scripts/check-app-store-build-status.sh" "ASC_REQUIRE_BETA_GROUPS" "App Store Connect script can require TestFlight beta group linkage"
require_pattern "scripts/check-app-store-build-status.sh" "ASC_EXPECTED_BETA_GROUP_NAME" "App Store Connect script can check the expected TestFlight group"
require_pattern "scripts/check-app-store-build-status.sh" "/v1/builds/#\\{URI\\.encode_www_form_component\\(build\\.fetch\\(\"id\"\\)\\)\\}/betaGroups" "App Store Connect script checks build beta group linkage"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  abort "wrong bundle id" unless data.dig("appInfo", "bundleId") == "com.h19h29.naymnaymlevelup"
  abort "wrong version" unless data.dig("appInfo", "version") == "1.0"
  abort "wrong build" unless data.dig("appInfo", "build") == ENV.fetch("RELEASE_BUILD_NUMBER", "15")
  abort "wrong privacy url" unless data.dig("urls", "privacyPolicy") == "https://h19h29-design.github.io/naymnaym/privacy.html"
  data_types = data.dig("appPrivacy", "dataTypes") || []
  required = ["Other User Content", "Photos or Videos", "Health and Fitness", "User ID"]
  required.each do |name|
    row = data_types.find { |item| item["name"] == name }
    abort "missing privacy data type #{name}" unless row
    abort "#{name} must be collected" unless row["collected"] == true
    abort "#{name} purpose must be App Functionality" unless row["purpose"] == "App Functionality"
    abort "#{name} must be linked" unless row["linkedToUser"] == true
    abort "#{name} must not track" unless row["tracking"] == false
  end
' "release/AppStoreMetadata/app-store-connect-values.json"
pass "App Store Connect values JSON"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  abort "wrong CloudKit container" unless data["containerIdentifier"] == "iCloud.com.h19h29.naymnaymlevelup"
  abort "wrong CloudKit database" unless data["database"] == "public"
  expected = {
    "ParentLink" => ["inviteCode"],
    "SharedMealRecord" => ["childLinkId"],
    "SharedChallengeRecord" => ["childLinkId"],
    "SharedMealPhoto" => ["childLinkId"]
  }
  record_types = data.fetch("recordTypes")
  expected.each do |name, queryable_fields|
    record = record_types.find { |item| item["name"] == name }
    abort "missing CloudKit record type #{name}" unless record
    field_names = record.fetch("fields").map { |field| field.fetch("name") }
    queryable_fields.each do |field|
      abort "#{name} missing field #{field}" unless field_names.include?(field)
      index = record.fetch("indexes").find { |item| item["field"] == field }
      abort "#{name}.#{field} missing queryable index" unless index && index["queryable"] == true
      abort "#{name}.#{field} should not require sortable index" unless index["sortable"] == false
    end
  end
  forbidden = data.fetch("forbiddenRecordTypes")
  ["PublicFeed", "Friend", "TeacherDashboard", "SchoolStats", "ChatMessage"].each do |name|
    abort "missing forbidden record marker #{name}" unless forbidden.include?(name)
  end
' "release/CloudKit/schema-contract.json"
pass "CloudKit schema contract JSON"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  release = data.fetch("releaseCandidate")
  abort "wrong release bundle id" unless release["bundleId"] == "com.h19h29.naymnaymlevelup"
  abort "wrong release version" unless release["version"] == "1.0"
  abort "wrong release build" unless release["build"] == ENV.fetch("RELEASE_BUILD_NUMBER", "15")
  abort "wrong release status" unless release["status"] == "uploaded_to_testflight_cli_processing_unconfirmed"

  decision = data.fetch("decision")
  abort "wrong candidate build" unless decision["currentCandidateBuild"] == ENV.fetch("RELEASE_BUILD_NUMBER", "15")
  rejected = decision.fetch("previousBuildsNotForRelease")
  build14 = rejected.find { |item| item["build"] == "14" }
  abort "build 14 rejection missing" unless build14
  abort "build 14 rejection must mention CloudKit entitlements" unless build14["reason"].include?("CloudKit")

  verified = data.fetch("verifiedLocalScope")
  {
    "sampleDataOnlyInDemoMode" => true,
    "missingAPIKeyDoesNotShowSampleMeals" => true,
    "todayMealDoesNotFallbackToMonthlyFirst" => true,
    "allergyChallengeLock" => true,
    "unsafeAllergyChallengeCopyBlockedByReleaseGate" => true,
    "shareCardsExcludeSensitiveFields" => true,
    "photoRecordEvidenceCoveredByReleaseGate" => true,
    "privacyManifestDataTypesMatchAppPrivacyDraft" => true,
    "unfinishedAppCopyBlockedByReleaseGate" => true,
    "cloudKitStorageCopyAlignedWithPrivacyDraft" => true,
    "koreanReleaseCopySpacingChecked" => true,
    "marketingSiteUsesReleaseReadyCopy" => true,
    "cloudKitEntitlementsVerifiedInBuild15IPA" => true,
    "appStoreConnectBetaGroupCheckScript" => true,
    "testFlightCliUploadSucceeded" => true
  }.each do |key, expected|
    abort "#{key} must be #{expected}" unless verified[key] == expected
  end

  xp = verified.fetch("xpCategories")
  ["record", "challenge", "balance", "safety"].each do |category|
    abort "missing xp category #{category}" unless xp.include?(category)
  end

  paths = data.fetch("evidencePaths")
  {
    "signedIPA" => "build/TestFlightExportBuild15Signed/NaymNaymLevelUp.ipa",
    "uploadLog" => "build/build15-signed-upload.log",
    "appStoreScreenshots" => "docs/app-store-screenshots/iphone-6-9-upload/",
    "appStoreConnectValues" => "release/AppStoreMetadata/app-store-connect-values.json",
    "cloudKitSchemaContract" => "release/CloudKit/schema-contract.json"
  }.each do |key, expected|
    abort "#{key} evidence path mismatch" unless paths[key] == expected
  end

  blockers = data.fetch("externalBlockers")
  ["App Store Connect", "TestFlight", "CloudKit Dashboard", "App Privacy", "App Review"].each do |area|
    abort "missing external blocker #{area}" unless blockers.any? { |item| item["area"] == area }
  end
' "release/ReleaseStatus/build-15-readiness.json"
pass "build 15 release status JSON"

git check-ignore -q Config.xcconfig || fail "Config.xcconfig must stay ignored"
pass "Config.xcconfig is ignored"
require_not_tracked "Config.xcconfig"

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
require_missing_plist_key "NaymNaymLevelUp/App/Info.plist" "NSUserTrackingUsageDescription"
require_missing_plist_key "NaymNaymLevelUp/App/Info.plist" "NSLocationWhenInUseUsageDescription"
require_missing_plist_key "NaymNaymLevelUp/App/Info.plist" "NSLocationAlwaysAndWhenInUseUsageDescription"
require_plist_value "NaymNaymLevelUp/NaymNaymLevelUp.entitlements" "com.apple.developer.icloud-container-identifiers:0" "iCloud.com.h19h29.naymnaymlevelup"
require_plist_value "NaymNaymLevelUp/NaymNaymLevelUp.entitlements" "com.apple.developer.icloud-services:0" "CloudKit"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1\\.0;" "App marketing version is 1.0"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "CURRENT_PROJECT_VERSION = ${RELEASE_BUILD_NUMBER};" "App build number is ${RELEASE_BUILD_NUMBER}"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = \"com\\.h19h29\\.naymnaymlevelup\";" "Bundle ID is com.h19h29.naymnaymlevelup"
require_pattern "NaymNaymLevelUp.xcodeproj/project.pbxproj" "TARGETED_DEVICE_FAMILY = 1;" "App target is iPhone only for App Store screenshot set"
require_pattern "docs/APP_STORE_METADATA.md" "^- 버전: 1\\.0$" "App Store metadata version is 1.0"
require_pattern "docs/APP_STORE_METADATA.md" "^- 빌드: ${RELEASE_BUILD_NUMBER}$" "App Store metadata build is ${RELEASE_BUILD_NUMBER}"
require_pattern "release/AppStoreMetadata/ko-KR.md" "^- 버전: 1\\.0$" "ko-KR metadata version is 1.0"
require_pattern "release/AppStoreMetadata/ko-KR.md" "^- 빌드: ${RELEASE_BUILD_NUMBER}$" "ko-KR metadata build is ${RELEASE_BUILD_NUMBER}"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "App Store Connect 입력 매트릭스" "App Privacy draft includes input matrix"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "Other User Content \\| 수집함 \\| App Functionality \\| 예 \\| 아니요" "App Privacy draft covers other user content"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "Photos or Videos \\| 수집함 \\| App Functionality \\| 예 \\| 아니요" "App Privacy draft covers photos or videos"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "Health and Fitness \\| 수집함 \\| App Functionality \\| 예 \\| 아니요" "App Privacy draft covers health and fitness"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "User ID \\| 수집함 \\| App Functionality \\| 예 \\| 아니요" "App Privacy draft covers user id"
require_pattern "release/AppStoreMetadata/ko-KR.md" "Photos or Videos: 보수 입력 기준 수집함" "ko-KR metadata references photos privacy input"
require_pattern "release/AppStoreMetadata/ko-KR.md" "app-store-connect-values\\.json" "ko-KR metadata references structured values JSON"
require_pattern "README.md" "scripts/check-app-store-build-status\\.sh" "README references App Store Connect build status script"
require_pattern "README.md" "app-store-connect-values\\.json" "README references structured App Store Connect values"
require_pattern "README.md" "release/CloudKit/schema-contract\\.json" "README references CloudKit schema contract"
require_pattern "README.md" 'App Privacy 정보는 `release/AppStoreMetadata/app-privacy-draft\.md`의 입력 매트릭스 기준' "README references App Privacy input matrix"

require_plist_value "NaymNaymLevelUp/PrivacyInfo.xcprivacy" "NSPrivacyTracking" "false"
require_empty_plist_array "NaymNaymLevelUp/PrivacyInfo.xcprivacy" "NSPrivacyTrackingDomains"
ruby -rjson -e '
  data = JSON.parse(`plutil -convert json -o - #{ARGV.fetch(0).dump}`)
  abort "privacy tracking must be false" unless data["NSPrivacyTracking"] == false
  abort "privacy tracking domains must be empty" unless data["NSPrivacyTrackingDomains"] == []

  accessed = data.fetch("NSPrivacyAccessedAPITypes")
  user_defaults = accessed.find { |item| item["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults" }
  abort "UserDefaults required reason missing" unless user_defaults
  abort "UserDefaults reason CA92.1 missing" unless user_defaults.fetch("NSPrivacyAccessedAPITypeReasons").include?("CA92.1")

  required_types = [
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeHealth",
    "NSPrivacyCollectedDataTypeUserID"
  ]
  collected = data.fetch("NSPrivacyCollectedDataTypes")
  required_types.each do |name|
    row = collected.find { |item| item["NSPrivacyCollectedDataType"] == name }
    abort "missing Privacy Manifest data type #{name}" unless row
    abort "#{name} must be linked" unless row["NSPrivacyCollectedDataTypeLinked"] == true
    abort "#{name} must not track" unless row["NSPrivacyCollectedDataTypeTracking"] == false
    purposes = row.fetch("NSPrivacyCollectedDataTypePurposes")
    abort "#{name} must be App Functionality" unless purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
  end
' "NaymNaymLevelUp/PrivacyInfo.xcprivacy"
pass "Privacy Manifest collected data types match App Privacy draft"
require_absent_path "Package.swift"
require_absent_path "Package.resolved"
require_absent_path "Podfile"
require_absent_path "Podfile.lock"
require_absent_path "Cartfile"
require_absent_path "Cartfile.resolved"
require_absent_pattern "NaymNaymLevelUp NaymNaymLevelUp.xcodeproj" "Firebase|GoogleMobileAds|AdMob|AppTrackingTransparency|NSUserTrackingUsageDescription|FBSDK|AppsFlyer|Amplitude|Mixpanel|RevenueCat|StoreKit|CoreLocation|CLLocation|AuthenticationServices|SignInWithApple" "No ad, analytics, tracking, purchase, login, or location SDK references"
require_absent_pattern "NaymNaymLevelUp" "TODO|FIXME|HACK|placeholder|임시|나중|추후|미완료|개발 중|준비중|출시 예정" "No unfinished release copy or development markers in app source"
require_absent_pattern "NaymNaymLevelUp README.md docs release marketing-site/dist" "아이 폰|한입 도전|한입 도전자|한입 탐험가" "No awkward Korean release copy spacing"
require_absent_pattern "marketing-site/dist" "준비중|처리 확인 중|제출 전 검토|출시 준비 상태" "Marketing site uses release-ready copy instead of temporary status copy"
require_absent_pattern "NaymNaymLevelUp README.md docs release/AppStoreMetadata" "서버 저장 없음" "No misleading no-server-storage copy where CloudKit parent sharing can store selected data"
require_pattern "NaymNaymLevelUp/Views/Settings/SettingsView.swift" "부모 공유 시 iCloud 사용" "App info discloses iCloud use for parent sharing"
require_absent_pattern "NaymNaymLevelUp docs release README.md" "먹어도 괜찮|먹어도 안전|조금만 먹어보|AI가 안전|안전하다고 판단" "No unsafe allergy challenge or safety-guarantee copy"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" "보호자와 학교 안내" "Meal screen prioritizes guardian and school allergy guidance"
require_pattern "NaymNaymLevelUp/Views/Settings/SettingsView.swift" "학교 안내와 보호자 판단" "Settings privacy copy prioritizes school guidance and guardian judgment"
require_pattern "release/AppStoreMetadata/ko-KR.md" "학교 안내와 보호자 판단이 항상 우선" "App Store metadata includes allergy safety disclaimer"
require_file "docs/PHOTO_RECORD_RELEASE_EVIDENCE.md"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" "Section\\(\"급식판 사진\"\\)" "Meal detail includes photo record section"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" 'PhotosPicker\(selection: \$selectedPhotoItem, matching: \.images\)' "Meal detail includes photo picker"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" "Label\\(\"사진 찍기\", systemImage: \"camera\"\\)" "Meal detail includes camera action"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" "Toggle\\(\"부모에게 이 사진 공유\"" "Meal detail includes parent photo sharing toggle"
require_pattern "NaymNaymLevelUp/Views/Meals/TodayMealView.swift" "사진 공유는 이 기록 공유가 켜진 경우에만 선택할 수 있어요" "Photo sharing is gated by record sharing copy"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testLocalPhotoStoreSavesAndDeletesFile" "Photo local save/delete test exists"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testUpdateMealPhotoSharingClearsChildLinkWhenDisabled" "Photo sharing disable test exists"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testChildSummariesOnlyExposeParentSharedPhotosAndRecords" "Parent summary shared photo privacy test exists"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testCloudKitPhotoRecordRequiresBothPermissions" "CloudKit photo permission test exists"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testCloudKitSharedPhotoRecordFieldsMatchConsoleRunbook" "CloudKit shared photo contract test exists"
require_pattern "NaymNaymLevelUpTests/LocalStoreTests.swift" "testResetAllDataClearsProfileRecordsProgressParentLinksAndPhotoFiles" "Full reset deletes photo files test exists"
require_pattern "release/AppStoreMetadata/app-privacy-draft.md" "Photos or Videos \\| 수집함 \\| App Functionality \\| 예 \\| 아니요" "App Privacy draft covers photo records"

require_file "$RELEASE_UPLOAD_LOG"
require_file "${RELEASE_EXPORT_DIR}/ExportOptions.plist"
require_pattern "$RELEASE_UPLOAD_LOG" "Uploaded NaymNaymLevelUp" "build ${RELEASE_BUILD_NUMBER} upload log has app upload marker"
require_pattern "$RELEASE_UPLOAD_LOG" "EXPORT SUCCEEDED" "build ${RELEASE_BUILD_NUMBER} upload command succeeded"
require_not_tracked "$RELEASE_UPLOAD_LOG"
check_uploaded_ipa "$RELEASE_IPA_PATH" "$RELEASE_BUILD_NUMBER"

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
[ "$count" = "10" ] || fail "App Store screenshot count is $count, expected exactly 10"
pass "App Store screenshot count is $count"

for required_screenshot in \
  01-onboarding.jpg \
  02-today-meal.jpg \
  03-one-bite.jpg \
  04-levelup.jpg \
  05-parent-summary.jpg \
  06-allergy-safety.jpg \
  07-share-card.jpg \
  08-monthly-calendar-live.jpg \
  09-settings-privacy-support.jpg \
  10-support-guide.jpg
do
  require_file "docs/app-store-screenshots/iphone-6-9-upload/$required_screenshot"
done

for url in \
  "https://h19h29-design.github.io/naymnaym/" \
  "https://h19h29-design.github.io/naymnaym/privacy.html" \
  "https://h19h29-design.github.io/naymnaym/support.html" \
  "https://h19h29-design.github.io/naymnaym/data-safety.html"
do
  check_url "$url"
done

pass "release readiness checks completed"
