# 냠냠레벨업 네이티브 재구축 출시 준비 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 새 네이티브 구현의 기능 동등성, 기록 이전, 접근성, 성능, 개인정보, 딥링크를 검증하고 스토어 업로드 전의 베타 후보 빌드를 만든다.

**Architecture:** 공통 계약과 상태 매트릭스를 자동 검증하고, 플랫폼별 UI·접근성·성능 테스트를 하나의 release-readiness 스크립트로 묶는다. 기존 출시 앱과 서버는 새 클라이언트가 검증될 때까지 하위 호환 상태로 유지한다.

**Tech Stack:** XCTest/XCUITest, Android JUnit/Compose UI Test, Python 3, shell verification scripts, xctrace, adb, Deno tests, Xcode archive, Gradle bundle

## Global Constraints

- 앞선 기반·아이 급식·캐릭터·부모 동기화 계획이 모두 완료되어야 한다.
- Bundle ID/applicationId는 `com.h19h29.naymnaymlevelup`이다.
- iOS 16.0, Android minSdk 23·targetSdk 36 지원을 유지한다.
- 서버 v1 동작을 제거하지 않는다.
- 실제 스토어 업로드, TestFlight 제출, Google Play 트랙 업로드는 이 계획에 포함하지 않는다.
- 기능 플래그 기본값 변경은 모든 게이트 통과 후 별도 사용자 승인 단계로 남긴다.
- 광고·추적 SDK가 없는 상태를 유지한다.

## Target File Map

- `docs/qa/native-rebuild-feature-parity.md`: 기존/새 기능 대조
- `docs/qa/native-rebuild-accessibility-matrix.md`: 기기·글자·보조기술 상태
- `docs/qa/native-rebuild-migration-matrix.md`: 원본 버전별 이전 결과
- `docs/qa/native-rebuild-performance-budget.md`: 시작·프레임·메모리·에셋 기준
- `scripts/verify-native-rebuild-contracts.sh`: 공통 계약 게이트
- `scripts/verify-native-rebuild-accessibility.sh`: 정적 접근성 검사
- `scripts/verify-native-rebuild-migration.py`: 익명 fixture 이전 검증
- `scripts/verify-native-rebuild-release.sh`: 전체 로컬 출시 준비 게이트
- `NaymNaymLevelUpUITests/RebuildCriticalFlowUITests.swift`: iOS 핵심 흐름
- `android/app/src/androidTest/.../RebuildCriticalFlowTest.kt`: Android 핵심 흐름

---

### Task 1: 기존 기능 대조와 딥링크 동등성

**Files:**
- Create: `docs/qa/native-rebuild-feature-parity.md`
- Create: `contracts/native-rebuild/v1/deep-link-fixtures.json`
- Create: `NaymNaymLevelUpTests/RebuildDeepLinkTests.swift`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/RebuildDeepLinkTest.kt`
- Modify: iOS rebuild root/router files
- Modify: Android rebuild root/navigation files

**Interfaces:**
- Supports schemes: `nyamnyam`, `naymnaym`, `naymnaymlevelup`
- Supports hosts/paths: `nyam.h19h19.com/invite`, `/parent-invite`, `/child-invite`
- Produces routes: `parentSummary`, `childInvite`, `onboarding`

- [ ] **Step 1: Write the full parity matrix**

Rows must include:

```text
profile setup
school search
allergy selection
today meal
meal status and reasons
nutrition explanation
XP and daily cap
growth level
collection
monthly history
parent invite
parent summary
push registration
settings
data export
data deletion
all supported deep links
```

Each row contains legacy file, new iOS file, new Android file, automated test, manual state, and result.

- [ ] **Step 2: Add failing shared deep-link fixture tests**

```json
[
  {"url":"nyamnyam://parent-invite?code=ABC123","expected":"childInvite"},
  {"url":"https://nyam.h19h19.com/parent-invite?code=ABC123","expected":"childInvite"},
  {"url":"https://nyam.h19h19.com/child-invite?id=11111111-1111-1111-1111-111111111111","expected":"parentSummary"},
  {"url":"naymnaymlevelup://onboarding","expected":"onboarding"}
]
```

Load the same file in Swift and Kotlin tests.

- [ ] **Step 3: Implement rebuild routing**

Reject unknown hosts and paths, trim invite code whitespace, never log codes or session tokens, and route parent destinations through `GuardianGate`.

- [ ] **Step 4: Run route and full unit tests**

Run: XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/qa/native-rebuild-feature-parity.md contracts/native-rebuild/v1/deep-link-fixtures.json NaymNaymLevelUpTests android/app/src/test NaymNaymLevelUp/Rebuild android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild
git commit -m "test: close native rebuild feature parity"
```

### Task 2: 양 플랫폼 핵심 흐름 UI 자동화

**Files:**
- Create: `NaymNaymLevelUpUITests/RebuildCriticalFlowUITests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Modify: `NaymNaymLevelUp.xcodeproj/xcshareddata/xcschemes/NaymNaymLevelUp.xcscheme`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/RebuildCriticalFlowTest.kt`
- Create: `contracts/native-rebuild/v1/ui-test-seed.json`

**Interfaces:**
- Seeds: fixed school, meal, profile, XP, parent connection states
- Tests: child record flow and parent report flow without live network

- [ ] **Step 1: Add deterministic UI seed**

Seed date `2026-07-25`, menus `현미밥`, `시금치나물`, `우유`, profile `냠냠이`, starting XP `0`, and disconnected parent state. Both test apps load it only when launch argument `-rebuild-ui-test-seed` is present.

- [ ] **Step 2: Write failing iOS critical-flow test**

Create the `NaymNaymLevelUpUITests` UI-testing bundle target with product bundle identifier `com.h19h29.naymnaymlevelup.uitests`, deployment target 16.0, target application `NaymNaymLevelUp`, and add it to the shared scheme test action.

```swift
func testChildRecordsOneBiteAndParentSeesLocalSummary() {
    app.launchArguments += ["-native-rebuild-enabled", "YES", "-rebuild-ui-test-seed"]
    app.launch()
    app.buttons["아이로 시작"].tap()
    app.buttons["오늘 급식 기록하기"].tap()
    app.buttons["시금치나물, 한입도전"].tap()
    XCTAssertTrue(app.staticTexts["경험치 18을 받았어요"].waitForExistence(timeout: 2))
}
```

- [ ] **Step 3: Write the matched Compose critical-flow test**

Use test tags from the child and parent plans; assert the same 18 XP and `시금치나물` report content.

- [ ] **Step 4: Run UI tests**

Run: XcodeBuildMCP `test_sim` for the UI test target.

Run: `cd android && ./gradlew connectedDebugAndroidTest`

Expected: PASS without network access.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUpUITests NaymNaymLevelUp.xcodeproj/project.pbxproj NaymNaymLevelUp.xcodeproj/xcshareddata/xcschemes/NaymNaymLevelUp.xcscheme android/app/src/androidTest contracts/native-rebuild/v1/ui-test-seed.json
git commit -m "test: automate rebuild critical flows"
```

### Task 3: 글자·접근성·움직임 축소 게이트

**Files:**
- Create: `docs/qa/native-rebuild-accessibility-matrix.md`
- Create: `scripts/verify-native-rebuild-accessibility.sh`
- Create: `NaymNaymLevelUpUITests/RebuildAccessibilityUITests.swift`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/RebuildAccessibilityTest.kt`

**Interfaces:**
- Verifies: headings, labels, 48pt/dp actions, focus order, no color-only state, reduced motion
- Covers: small phone, large phone, iPad, small Android, standard Android

- [ ] **Step 1: Add exact accessibility scenarios**

Matrix columns:

```text
screen
device/viewport
font scale
VoiceOver/TalkBack order
Reduce Motion
truncated text
horizontal scrolling
result
```

Required font scales: iOS default and accessibility-extra-extra-extra-large; Android 1.0 and 2.0.

- [ ] **Step 2: Write failing automated assertions**

iOS checks button frames are at least 48×48 points and key texts have `exists == true` at large content size. Android checks `assertTouchHeightIsEqualTo(48.dp)` or greater, semantic headings, and visible text at fontScale 2.0.

- [ ] **Step 3: Fix every failing layout without shrinking body text**

Allowed fixes: vertical reflow, flexible frames, scroll containers, multiline labels, larger sheet detents. Forbidden fixes: reducing system font size, clipping, one-line truncation of menu names, hiding explanations.

- [ ] **Step 4: Run accessibility verification**

Run: `bash scripts/verify-native-rebuild-accessibility.sh`

Script content:

```bash
#!/usr/bin/env bash
set -euo pipefail
rg -n 'lineLimit\\(1\\)|minimumScaleFactor|fontSize *= *[0-9]+f' NaymNaymLevelUp/Rebuild android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild && exit 1 || true
(cd android && ./gradlew connectedDebugAndroidTest)
git diff --check
echo "native-rebuild-accessibility: PASS"
```

Run iOS UI tests with XcodeBuildMCP. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/qa/native-rebuild-accessibility-matrix.md scripts/verify-native-rebuild-accessibility.sh NaymNaymLevelUpUITests/RebuildAccessibilityUITests.swift android/app/src/androidTest
git commit -m "test: enforce readable accessible layouts"
```

### Task 4: 실제 이전 데이터 fixture와 실패 복구

**Files:**
- Create: `tests/fixtures/migration/ios-v1-userdefaults.json`
- Create: `tests/fixtures/migration/android-test7-preferences.json`
- Create: `tests/fixtures/migration/expected-v1.json`
- Create: `scripts/verify-native-rebuild-migration.py`
- Create: `docs/qa/native-rebuild-migration-matrix.md`
- Modify: platform migration tests

**Interfaces:**
- Verifies: profile, allergies, meal records, challenge records, XP total, level, parent-link transition
- Guarantees: source digest unchanged after success and forced failure

- [ ] **Step 1: Export and anonymize representative legacy fixtures**

Use only synthetic names and schools. Include:

- no profile
- child with 20 meal records and multiple statuses including `half`
- parent with one connected child
- pending invite
- malformed single record among valid records
- progress at every growth-level boundary

- [ ] **Step 2: Write the failing cross-fixture verifier**

```python
def assert_migration(actual, expected):
    assert actual["profileCount"] == expected["profileCount"]
    assert actual["mealRecordCount"] == expected["mealRecordCount"]
    assert actual["xpTotal"] == expected["xpTotal"]
    assert actual["growthLevel"] == expected["growthLevel"]
    assert actual["sourceDigestBefore"] == actual["sourceDigestAfter"]
```

The script invokes platform test harnesses with fixture paths and fails on any mismatch.

- [ ] **Step 3: Fix migration mapping and failure isolation**

Map legacy `half` to persisted `half`, not `finished`. Skip only the malformed record, return a warning count, and do not mark migration complete if profile or XP totals cannot be verified.

- [ ] **Step 4: Run migration soak**

Run: `python3 scripts/verify-native-rebuild-migration.py --repeat 50`

Expected: 50 identical PASS results, unchanged source digests, no duplicate XP events.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/migration scripts/verify-native-rebuild-migration.py docs/qa/native-rebuild-migration-matrix.md NaymNaymLevelUpTests android/app/src/test
git commit -m "test: prove legacy migration safety"
```

### Task 5: 성능·메모리·에셋 예산

**Files:**
- Create: `docs/qa/native-rebuild-performance-budget.md`
- Create: `scripts/check-mascot-asset-budget.py`
- Create: `scripts/measure-android-rebuild.sh`
- Create: `NaymNaymLevelUpTests/RebuildPerformanceTests.swift`

**Interfaces:**
- Budget: warm app interactive ≤ 2.0s on reference simulator/emulator
- Budget: no post-warm mascot frame > 32ms
- Budget: decoded mascot level ≤ 80MB peak
- Budget: app-bundled mascot PNG bytes ≤ 30MB total per platform

- [ ] **Step 1: Write failing budget checks**

The asset script sums production rig PNG sizes and rejects missing levels, non-RGBA files, and totals over 30MB. XCTest measures 20 iterations of weekly report and meal recording use cases.

- [ ] **Step 2: Measure current candidate**

Run: `python3 scripts/check-mascot-asset-budget.py`

Run: `bash scripts/measure-android-rebuild.sh`

Run iOS performance tests with XcodeBuildMCP.

Expected: measurements recorded even if a budget initially fails.

- [ ] **Step 3: Apply deterministic optimizations**

Downscale only if the rendered pixel size never needs 1254px, use lossless PNG optimization, preload only the active level, release inactive decoded images, avoid recomputing weekly reports during scroll, and batch Room/Core Data fetches.

- [ ] **Step 4: Re-run and record passing measurements**

All four budgets must pass and be copied into `native-rebuild-performance-budget.md` with device names and OS versions.

- [ ] **Step 5: Commit**

```bash
git add docs/qa/native-rebuild-performance-budget.md scripts/check-mascot-asset-budget.py scripts/measure-android-rebuild.sh NaymNaymLevelUpTests/RebuildPerformanceTests.swift
git commit -m "perf: enforce native rebuild budgets"
```

### Task 6: 개인정보·백업·릴리스 선언 검증

**Files:**
- Modify: `NaymNaymLevelUp/PrivacyInfo.xcprivacy`
- Modify: `NaymNaymLevelUp/App/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/xml/data_extraction_rules.xml`
- Create: `android/app/src/main/res/xml/backup_rules.xml`
- Modify: `release/AppStoreMetadata/*` only where descriptions no longer match
- Modify: `release/GooglePlayMetadata/*` only where descriptions no longer match
- Modify: `scripts/verify-release-readiness.sh`

**Interfaces:**
- Excludes: parent session token, database, invite secret, push token from cloud backup
- Declares: only APIs and data actually used by the rebuilt app

- [ ] **Step 1: Add failing static privacy checks**

Extend the script to fail when:

```text
android:allowBackup="true" without dataExtractionRules
parent session preference is not excluded
NSPrivacyTracking is true
AdSupport, FirebaseAnalytics, or advertising identifiers appear in linked dependencies
```

- [ ] **Step 2: Run the release verifier**

Run: `bash scripts/verify-release-readiness.sh`

Expected: FAIL until backup and privacy declarations are updated.

- [ ] **Step 3: Add explicit platform declarations**

Use `dataExtractionRules` and `fullBackupContent` to exclude both app databases and secure-token preferences. Keep user-initiated JSON export separate from automatic backup. Update privacy manifest reasons for UserDefaults and file timestamps only when the rebuilt code still calls those APIs.

- [ ] **Step 4: Run privacy and release checks**

Run: `bash scripts/verify-release-readiness.sh`

Run: `rg -n 'ads|advertising|tracking|analytics' android/app/build.gradle NaymNaymLevelUp.xcodeproj/project.pbxproj`

Expected: verifier PASS and no ad/tracking dependencies.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/PrivacyInfo.xcprivacy NaymNaymLevelUp/App/Info.plist android/app/src/main/AndroidManifest.xml android/app/src/main/res/xml release scripts/verify-release-readiness.sh
git commit -m "chore: align rebuild privacy declarations"
```

### Task 7: 통합 release-readiness 게이트와 베타 후보

**Files:**
- Create: `scripts/verify-native-rebuild-contracts.sh`
- Create: `scripts/verify-native-rebuild-release.sh`
- Create: `docs/qa/native-rebuild-release-signoff.md`
- Modify: build configuration only after explicit flag-activation approval

**Interfaces:**
- Produces: local iOS archive and Android AAB after all tests
- Does not upload either artifact

- [ ] **Step 1: Compose the complete local gate**

```bash
#!/usr/bin/env bash
set -euo pipefail
python3 scripts/tests/test_native_rebuild_contracts.py
bash scripts/sync-native-rebuild-contracts.sh
python3 scripts/tests/test_validate_mascot_rig.py
python3 scripts/validate-mascot-rig.py --root art/mascot-rig
python3 scripts/verify-native-rebuild-migration.py --repeat 50
deno test supabase/functions/parent-sync/*_test.ts
(cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest bundleRelease)
bash scripts/verify-release-readiness.sh
git diff --check
echo "native-rebuild-release: PASS"
```

The iOS test and archive remain XcodeBuildMCP actions documented next to the script because Apple build tools are managed by the active Xcode session.

- [ ] **Step 2: Run all gates with flags still default-disabled**

Run: `bash scripts/verify-native-rebuild-release.sh`

Run: XcodeBuildMCP `test_sim`.

Run: XcodeBuildMCP archive/export workflow without upload.

Expected: PASS and local artifacts only.

- [ ] **Step 3: Review the signoff document**

Record commit SHA, iOS archive path, Android AAB path, test counts, migration repeat count, performance results, accessibility matrix result, privacy result, and known non-blocking limitations. The signoff must state `스토어 업로드 미수행`.

- [ ] **Step 4: Pause for explicit feature-flag activation approval**

Do not change the committed default from `false` until the user explicitly approves activating the rebuild in release builds. This checkpoint is required even when all tests pass.

- [ ] **Step 5: After approval, activate only release configuration and re-run**

iOS release builds return `true` from a compile-time `NATIVE_REBUILD_RELEASE` condition; debug still accepts the launch argument. Android release `buildConfigField` becomes `true`; debug remains `false`.

Re-run the complete gate and create new local artifacts. Do not upload them.

- [ ] **Step 6: Commit**

```bash
git add scripts/verify-native-rebuild-contracts.sh scripts/verify-native-rebuild-release.sh docs/qa/native-rebuild-release-signoff.md NaymNaymLevelUp android/app/build.gradle
git commit -m "build: prepare native rebuild beta candidate"
```

### Task 8: 베타 승인 후 레거시 런타임 제거

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Migration/LegacyDTOs.swift`
- Modify: `NaymNaymLevelUp/App/NaymNaymLevelUpApp.swift`
- Replace: `NaymNaymLevelUp/App/RootView.swift`
- Delete after migration tests pass: legacy iOS `AppState`, `Views`, `ViewModels`, `DesignSystem`, replaced services/stores/utils, and flattened Lottie runtime files
- Modify: `android/app/src/main/AndroidManifest.xml`
- Delete after migration tests pass: `android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java` and replaced Java policy/runtime files
- Modify: legacy migration readers to decode with standalone DTOs
- Modify: Xcode project target membership and legacy tests

**Interfaces:**
- Produces: rebuilt SwiftUI root as the only iOS runtime root
- Produces: `RebuildActivity` as the Android launcher and deep-link target
- Preserves: legacy storage key names and decoding structs inside migration-only files

- [ ] **Step 1: Pause for explicit beta signoff**

Require the completed `native-rebuild-release-signoff.md` and explicit user approval to remove the legacy runtime. Do not begin deletion from design approval alone.

- [ ] **Step 2: Extract immutable legacy decoders**

Move only the Codable fields required by migration fixtures into `LegacyDTOs.swift` and Kotlin migration DTOs. Verify they decode every committed legacy fixture before changing runtime files.

- [ ] **Step 3: Switch launchers**

iOS `RootView` becomes a thin wrapper around `RebuildRootView` plus migration start. Android manifest makes `.rebuild.RebuildActivity` exported and attaches every existing launcher/deep-link filter to it.

- [ ] **Step 4: Remove replaced runtime code and resources**

Delete files only when the parity matrix identifies a rebuilt owner and an automated test. Keep original 7 growth images as archival fallback assets; remove flattened pseudo-motion JSON/PNG files after the new rig validator and motion tests pass.

- [ ] **Step 5: Run the full gate twice**

Run: `bash scripts/verify-native-rebuild-release.sh`

Clean build outputs, then run the same command again.

Run: XcodeBuildMCP clean build, `test_sim`, and local archive.

Expected: two PASS runs with no compile reference to `MainActivity.java`, old `AppState`, or old view types.

- [ ] **Step 6: Commit**

```bash
git add -A NaymNaymLevelUp NaymNaymLevelUpTests NaymNaymLevelUpUITests NaymNaymLevelUp.xcodeproj android/app/src
git commit -m "refactor: remove verified legacy runtimes"
```
