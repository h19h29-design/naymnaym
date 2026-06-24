#!/bin/bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="NaymNaymLevelUp"
PROJECT_PATH="NaymNaymLevelUp.xcodeproj"
SCHEME="NaymNaymLevelUp"
TEAM_ID="47SNWAZN3G"
EXPECTED_BUNDLE_ID="com.h19h29.naymnaymlevelup"
EXPECTED_VERSION="1.0"
EXPECTED_ICLOUD_CONTAINER="iCloud.com.h19h29.naymnaymlevelup"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-FEDEF97987FC83EC65955EB899B96DBF7BBF2EA8}"
SIGNING_PREFLIGHT_TIMEOUT_SECONDS="${SIGNING_PREFLIGHT_TIMEOUT_SECONDS:-20}"

usage() {
  cat <<'EOF'
Usage:
  scripts/release-testflight-build.sh BUILD_NUMBER
  UPLOAD=1 scripts/release-testflight-build.sh BUILD_NUMBER

Creates a signed Release archive, exports an App Store Connect IPA, verifies the
IPA's embedded provisioning profile and signed app CloudKit entitlements, and
only uploads to TestFlight when UPLOAD=1 is set.

Before running:
  - Start from a clean git worktree.
  - Keep Config.xcconfig untracked.
  - If macOS asks for signing keychain/certificate access, allow it.
  - If signing preflight fails, unlock the keychain or allow codesign access,
    then rerun the same command.
  - Do not continue to upload unless scripts/inspect-ipa-entitlements.sh passes.
EOF
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

read_plist_first_or_scalar() {
  file="$1"
  key="$2"
  value="$(/usr/libexec/PlistBuddy -c "Print :${key}:0" "$file" 2>/dev/null || true)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true
}

require_value() {
  value="$1"
  expected="$2"
  description="$3"
  [ "$value" = "$expected" ] || fail "$description is '${value:-missing}', expected '$expected'"
  pass "$description is $expected"
}

write_export_options() {
  destination="$1"
  output="$2"

  cat >"$output" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>$destination</string>
	<key>generateAppStoreInformation</key>
	<false/>
	<key>iCloudContainerEnvironment</key>
	<string>Production</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>testFlightInternalTestingOnly</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF
}

run_and_log() {
  log_file="$1"
  shift

  mkdir -p "$(dirname "$log_file")"
  printf 'Running:'
  printf ' %q' "$@"
  printf '\n'

  if "$@" >"$log_file" 2>&1; then
    tail -n 80 "$log_file"
    return
  fi

  status=$?
  tail -n 160 "$log_file" >&2 || true
  fail "command failed with exit $status; see $log_file"
}

inspect_archive_app() {
  archive_path="$1"
  expected_build="$2"
  app_dir="$archive_path/Products/Applications/${APP_NAME}.app"
  [ -d "$app_dir" ] || fail "Missing archived app: $app_dir"

  info_plist="$app_dir/Info.plist"
  require_value "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)" "$EXPECTED_BUNDLE_ID" "archive bundle identifier"
  require_value "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)" "$EXPECTED_VERSION" "archive marketing version"
  require_value "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)" "$expected_build" "archive build number"

  entitlements_file="$archive_path/signed-app-entitlements.plist"
  codesign -d --entitlements :- "$app_dir" >"$entitlements_file" 2>/dev/null || fail "archived app signed entitlements could not be read"
  [ -s "$entitlements_file" ] || fail "archived app signed entitlements are empty"

  signed_container="$(read_plist_first_or_scalar "$entitlements_file" "com.apple.developer.icloud-container-identifiers")"
  signed_service="$(read_plist_first_or_scalar "$entitlements_file" "com.apple.developer.icloud-services")"
  require_value "$signed_container" "$EXPECTED_ICLOUD_CONTAINER" "archive signed app iCloud container entitlement"
  require_value "$signed_service" "CloudKit" "archive signed app CloudKit service entitlement"
}

preflight_signing_access() {
  tmp_dir="$(mktemp -d)"
  test_binary="$tmp_dir/true-test"
  cp /usr/bin/true "$test_binary"

  /usr/bin/codesign --dryrun --force --sign "$SIGNING_IDENTITY" "$test_binary" >"$tmp_dir/codesign.out" 2>"$tmp_dir/codesign.err" &
  pid=$!
  elapsed=0

  while [ "$elapsed" -lt "$SIGNING_PREFLIGHT_TIMEOUT_SECONDS" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if wait "$pid"; then
        rm -rf "$tmp_dir"
        pass "codesign keychain access preflight passed"
        return
      fi

      status=$?
      cat "$tmp_dir/codesign.err" >&2 || true
      rm -rf "$tmp_dir"
      fail "codesign keychain access preflight failed with exit $status"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  cat "$tmp_dir/codesign.err" >&2 || true
  rm -rf "$tmp_dir"
  fail "codesign keychain access preflight timed out after ${SIGNING_PREFLIGHT_TIMEOUT_SECONDS}s; allow signing keychain/certificate access and rerun"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

[ "$#" -eq 1 ] || {
  usage >&2
  exit 1
}

BUILD_NUMBER="$1"
case "$BUILD_NUMBER" in
  ''|*[!0-9]*)
    fail "BUILD_NUMBER must be a positive integer"
    ;;
esac
[ "$BUILD_NUMBER" -gt 0 ] || fail "BUILD_NUMBER must be greater than zero"

git diff --quiet || fail "Worktree has unstaged changes; commit or stash before release"
git diff --cached --quiet || fail "Worktree has staged changes; commit or unstage before release"
untracked_files="$(git ls-files --others --exclude-standard)"
[ -z "$untracked_files" ] || fail "Worktree has untracked files; commit, remove, or ignore them before release: $untracked_files"
git check-ignore -q Config.xcconfig || fail "Config.xcconfig must stay ignored"
if git ls-files --error-unmatch Config.xcconfig >/dev/null 2>&1; then
  fail "Config.xcconfig must not be tracked by Git"
fi

mkdir -p build

ARCHIVE_PATH="build/${APP_NAME}-build${BUILD_NUMBER}-signed.xcarchive"
EXPORT_PATH="build/TestFlightExportBuild${BUILD_NUMBER}Signed"
UPLOAD_PATH="build/TestFlightUploadBuild${BUILD_NUMBER}Signed"
EXPORT_OPTIONS="build/ExportOptions-Build${BUILD_NUMBER}-Signed.plist"
UPLOAD_OPTIONS="build/ExportOptions-Build${BUILD_NUMBER}-Upload.plist"
ARCHIVE_LOG="build/build${BUILD_NUMBER}-signed-archive.log"
EXPORT_LOG="build/build${BUILD_NUMBER}-signed-export.log"
UPLOAD_LOG="build/build${BUILD_NUMBER}-signed-upload.log"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$UPLOAD_PATH"
write_export_options "export" "$EXPORT_OPTIONS"
write_export_options "upload" "$UPLOAD_OPTIONS"

printf 'If macOS prompts for signing keychain/certificate access, allow it.\n'
preflight_signing_access

run_and_log "$ARCHIVE_LOG" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

inspect_archive_app "$ARCHIVE_PATH" "$BUILD_NUMBER"

run_and_log "$EXPORT_LOG" \
  xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_PATH="$EXPORT_PATH/${APP_NAME}.ipa"
EXPECTED_BUNDLE_ID="$EXPECTED_BUNDLE_ID" \
EXPECTED_VERSION="$EXPECTED_VERSION" \
EXPECTED_ICLOUD_CONTAINER="$EXPECTED_ICLOUD_CONTAINER" \
  scripts/inspect-ipa-entitlements.sh "$IPA_PATH"

if [ "${UPLOAD:-0}" = "1" ]; then
  run_and_log "$UPLOAD_LOG" \
    xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$UPLOAD_PATH" \
    -exportOptionsPlist "$UPLOAD_OPTIONS" \
    -allowProvisioningUpdates

  grep -Eq "Uploaded ${APP_NAME}" "$UPLOAD_LOG" || fail "upload log does not contain the app upload marker"
  grep -Eq "EXPORT SUCCEEDED" "$UPLOAD_LOG" || fail "upload log does not contain the export success marker"
  pass "build $BUILD_NUMBER upload command completed; confirm processing in App Store Connect"
else
  pass "build $BUILD_NUMBER export verified. Re-run with UPLOAD=1 to upload after confirming this build is intended for TestFlight."
fi
