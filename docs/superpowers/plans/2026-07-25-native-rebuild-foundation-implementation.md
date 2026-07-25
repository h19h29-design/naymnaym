# 냠냠레벨업 네이티브 재구축 기반 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 출시 화면을 유지한 채 새 네이티브 앱의 공통 계약, 비활성 루트, 로컬 데이터베이스, 기존 기록 이전 기반을 구축한다.

**Architecture:** 플랫폼 중립 JSON 계약을 테스트 기준으로 삼고, iOS는 SwiftUI·Core Data, Android는 Kotlin Compose·Room으로 별도 구현한다. 새 루트는 기능 플래그 뒤에 두며 기존 저장 원본을 삭제하지 않는 멱등 마이그레이션을 사용한다.

**Tech Stack:** Python 3 표준 라이브러리, Swift 5, SwiftUI, Core Data, XCTest, Kotlin 2.2.21, Compose BOM 2025.12.01, Room 2.8.4, JUnit 4

## Global Constraints

- iOS 최소 버전은 16.0이다.
- Android `minSdk 23`, `targetSdk 36`, `compileSdk 36`이다.
- Bundle ID와 applicationId는 `com.h19h29.naymnaymlevelup`이다.
- `native-rebuild-enabled`의 기본값은 `false`다.
- 기존 `RootView`, `MainActivity`, UserDefaults, SharedPreferences 데이터는 이 계획에서 제거하지 않는다.
- 광고·행동 추적 의존성을 추가하지 않는다.
- Android는 현재 AGP 8.9.1과 Gradle 8.11.1을 유지한다.
- 스토어 업로드와 배포는 수행하지 않는다.

## Target File Map

### 공통

- `contracts/native-rebuild/v1/domain-contract.json`: 역할, 식사 상태, 동기화 상태, 모션 상태의 canonical 값
- `contracts/native-rebuild/v1/domain-fixtures.json`: 양 플랫폼이 같은 결과를 내야 하는 고정 입력·출력
- `scripts/validate-native-rebuild-contracts.py`: 계약 스키마와 중복 값 검증
- `scripts/tests/test_native_rebuild_contracts.py`: 계약 검증 회귀 테스트

### iOS

- `NaymNaymLevelUp/Rebuild/Foundation/RebuildFeatureGate.swift`: 새 루트 활성화 판정
- `NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift`: 새 앱의 임시 역할 루트
- `NaymNaymLevelUp/Rebuild/Data/RebuildManagedModel.swift`: Core Data 모델
- `NaymNaymLevelUp/Rebuild/Data/RebuildPersistentStore.swift`: 영구·인메모리 컨테이너
- `NaymNaymLevelUp/Rebuild/Data/RebuildRepositories.swift`: 저장소 프로토콜과 Core Data 구현
- `NaymNaymLevelUp/Rebuild/Migration/LegacyDefaultsReader.swift`: 기존 UserDefaults 읽기
- `NaymNaymLevelUp/Rebuild/Migration/RebuildMigrationCoordinator.swift`: 원본 보존형 이전

### Android

- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/RebuildActivity.kt`: Compose 호스트
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/foundation/RebuildFeatureGate.kt`: 새 루트 활성화 판정
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt`: 새 앱의 임시 역할 루트
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildEntities.kt`: Room 엔터티
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDao.kt`: Room DAO
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDatabase.kt`: Room 데이터베이스
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/migration/LegacyPreferencesReader.kt`: 기존 SharedPreferences 읽기
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/migration/RebuildMigrationCoordinator.kt`: 원본 보존형 이전

---

### Task 1: 플랫폼 중립 계약과 고정 테스트 벡터

**Files:**
- Create: `contracts/native-rebuild/v1/domain-contract.json`
- Create: `contracts/native-rebuild/v1/domain-fixtures.json`
- Create: `scripts/validate-native-rebuild-contracts.py`
- Create: `scripts/sync-native-rebuild-contracts.sh`
- Create: `scripts/tests/test_native_rebuild_contracts.py`
- Create: `NaymNaymLevelUp/Resources/RebuildContracts/domain-contract.json`
- Create: `NaymNaymLevelUp/Resources/RebuildContracts/domain-fixtures.json`
- Create: `android/app/src/main/assets/rebuild-contracts/domain-contract.json`
- Create: `android/app/src/main/assets/rebuild-contracts/domain-fixtures.json`

**Interfaces:**
- Produces: canonical arrays `userRoles`, `eatingStatuses`, `syncStates`, `motionStates`
- Produces: `recordIdentity = "{date}|{normalizedMenuName}|{status}"`
- Produces: `progressEventIdentity = "meal:{recordIdentity}"`

- [ ] **Step 1: Write the failing contract test**

```python
import json
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class NativeRebuildContractTests(unittest.TestCase):
    def test_contract_has_exact_v1_values(self):
        contract = json.loads((ROOT / "contracts/native-rebuild/v1/domain-contract.json").read_text())
        self.assertEqual(contract["version"], 1)
        self.assertEqual(contract["userRoles"], ["child", "parent"])
        self.assertEqual(contract["eatingStatuses"], [
            "oneBite", "finished", "half", "smelledOnly", "difficultToday", "allergyAvoided"
        ])
        self.assertEqual(contract["recordableEatingStatuses"], [
            "oneBite", "finished", "smelledOnly", "difficultToday", "allergyAvoided"
        ])
        self.assertEqual(contract["syncStates"], ["localOnly", "queued", "synced", "failed", "deleted"])
        self.assertEqual(contract["motionStates"], [
            "idle", "tapReaction", "mealSuccess", "levelUp", "comfort", "reducedMotion"
        ])

    def test_validator_accepts_committed_contracts(self):
        result = subprocess.run(
            ["python3", "scripts/validate-native-rebuild-contracts.py"],
            cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify the missing-file failure**

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Expected: FAIL with `FileNotFoundError` for `domain-contract.json`.

- [ ] **Step 3: Add the exact v1 contracts**

```json
{
  "version": 1,
  "userRoles": ["child", "parent"],
  "eatingStatuses": ["oneBite", "finished", "half", "smelledOnly", "difficultToday", "allergyAvoided"],
  "recordableEatingStatuses": ["oneBite", "finished", "smelledOnly", "difficultToday", "allergyAvoided"],
  "syncStates": ["localOnly", "queued", "synced", "failed", "deleted"],
  "motionStates": ["idle", "tapReaction", "mealSuccess", "levelUp", "comfort", "reducedMotion"],
  "identityRules": {
    "recordIdentity": "{date}|{normalizedMenuName}|{status}",
    "progressEventIdentity": "meal:{recordIdentity}"
  }
}
```

`domain-fixtures.json` must contain these two deterministic examples:

```json
{
  "version": 1,
  "recordIdentities": [
    {
      "date": "2026-07-25",
      "menuName": " 시금치 나물 ",
      "status": "oneBite",
      "expected": "2026-07-25|시금치 나물|oneBite"
    },
    {
      "date": "2026-07-25",
      "menuName": "현미밥",
      "status": "finished",
      "expected": "2026-07-25|현미밥|finished"
    }
  ]
}
```

Implement the validator with `json`, `pathlib`, uniqueness checks, exact version checks, and exit code `1` on validation errors.

Add a sync script that copies every canonical `contracts/native-rebuild/v1/*.json` file to both runtime resource directories and then compares `shasum -a 256` values. The script must delete only stale `*.json` files inside the two generated resource directories, never files outside them.

- [ ] **Step 4: Run contract tests**

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Expected: `native-rebuild-contract-sync: PASS`.

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add contracts/native-rebuild scripts/validate-native-rebuild-contracts.py scripts/sync-native-rebuild-contracts.sh scripts/tests/test_native_rebuild_contracts.py NaymNaymLevelUp/Resources/RebuildContracts android/app/src/main/assets/rebuild-contracts
git commit -m "test: define native rebuild contracts"
```

### Task 2: 공통 디자인 토큰과 iOS 테마

**Files:**
- Create: `contracts/native-rebuild/v1/design-tokens.json`
- Create: `NaymNaymLevelUp/Rebuild/Foundation/RebuildDesignTokens.swift`
- Create: `NaymNaymLevelUpTests/RebuildDesignTokensTests.swift`
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces color IDs: `forest700`, `forest500`, `leaf300`, `cream50`, `cream100`, `ink900`, `muted600`, `danger700`
- Produces spacing `[4, 8, 12, 16, 24, 32]`
- Produces radii `[12, 20, 28]`
- Produces minimum action size `48`
- Guarantees: system fonts only for body, button, menu, and nutrition copy

- [ ] **Step 1: Write the failing iOS token test**

```swift
func testApprovedTokensAreExact() {
    XCTAssertEqual(RebuildDesignTokens.minimumActionSize, 48)
    XCTAssertEqual(RebuildDesignTokens.spacing, [4, 8, 12, 16, 24, 32])
    XCTAssertEqual(RebuildDesignTokens.hex(.forest700), "#1F5E43")
    XCTAssertEqual(RebuildDesignTokens.hex(.cream50), "#FFF9EC")
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildDesignTokensTests"]`.

Expected: FAIL because `RebuildDesignTokens` does not exist.

- [ ] **Step 3: Create the canonical JSON and iOS mapping**

```json
{
  "version": 1,
  "colors": {
    "forest700": "#1F5E43",
    "forest500": "#2F8A61",
    "leaf300": "#CBEA78",
    "cream50": "#FFF9EC",
    "cream100": "#F5EEDC",
    "ink900": "#183127",
    "muted600": "#627168",
    "danger700": "#A33A35"
  },
  "spacing": [4, 8, 12, 16, 24, 32],
  "radii": [12, 20, 28],
  "minimumActionSize": 48,
  "fontPolicy": "system-scalable"
}
```

Map the values to SwiftUI `Color` and `CGFloat` without dynamic device colors. Add `NaymNaymLevelUp/Resources/RebuildContracts` to the application resources build phase exactly once. iOS text styles use `Font.body`, `headline`, and `title2`. Do not add a bundled body font.

- [ ] **Step 4: Run token validation and iOS tests**

Run: `python3 scripts/validate-native-rebuild-contracts.py`

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildDesignTokensTests"]`.

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add contracts/native-rebuild/v1/design-tokens.json scripts/validate-native-rebuild-contracts.py NaymNaymLevelUp/Rebuild/Foundation/RebuildDesignTokens.swift NaymNaymLevelUpTests/RebuildDesignTokensTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj NaymNaymLevelUp/Resources/RebuildContracts android/app/src/main/assets/rebuild-contracts
git commit -m "feat: add rebuild design tokens"
```

### Task 3: iOS 기능 플래그와 새 SwiftUI 루트

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Foundation/RebuildFeatureGate.swift`
- Create: `NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift`
- Modify: `NaymNaymLevelUp/App/RootView.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/RebuildFeatureGateTests.swift`

**Interfaces:**
- Produces: `RebuildFeatureGate.isEnabled(defaults:arguments:) -> Bool`
- Produces: `RebuildRootView: View`
- Consumes: UserDefaults key `native-rebuild-enabled`

- [ ] **Step 1: Write the failing feature-gate tests**

```swift
import XCTest
@testable import NaymNaymLevelUp

final class RebuildFeatureGateTests: XCTestCase {
    func testDefaultsToDisabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        XCTAssertFalse(RebuildFeatureGate.isEnabled(defaults: defaults, arguments: []))
    }

    func testLaunchArgumentEnablesRebuild() {
        let defaults = UserDefaults(suiteName: #function)!
        XCTAssertTrue(
            RebuildFeatureGate.isEnabled(
                defaults: defaults,
                arguments: ["-native-rebuild-enabled", "YES"]
            )
        )
    }
}
```

- [ ] **Step 2: Run the focused iOS test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildFeatureGateTests"]`.

Expected: FAIL because `RebuildFeatureGate` does not exist.

- [ ] **Step 3: Implement the gate and minimal role-selection root**

```swift
enum RebuildFeatureGate {
    static func isEnabled(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if let index = arguments.firstIndex(of: "-native-rebuild-enabled"),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1].uppercased() == "YES"
        }
        return defaults.bool(forKey: "native-rebuild-enabled")
    }
}
```

`RebuildRootView` must show two large accessible controls, `아이로 시작` and `보호자로 시작`, without changing persisted legacy mode. In `RootView.body`, place this branch before the existing profile branch:

```swift
if RebuildFeatureGate.isEnabled() {
    RebuildRootView()
} else if appState.hasProfile {
    // existing branches unchanged
}
```

Add all new Swift files to the application or test target in `project.pbxproj`.

- [ ] **Step 4: Run focused and legacy tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildFeatureGateTests"]`.

Expected: PASS.

Run: XcodeBuildMCP `test_sim`.

Expected: all existing tests PASS with the default-disabled path.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild NaymNaymLevelUp/App/RootView.swift NaymNaymLevelUpTests/RebuildFeatureGateTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: add disabled iOS rebuild root"
```

### Task 4: iOS Core Data 모델과 저장소

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Data/RebuildManagedModel.swift`
- Create: `NaymNaymLevelUp/Rebuild/Data/RebuildPersistentStore.swift`
- Create: `NaymNaymLevelUp/Rebuild/Data/RebuildRepositories.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/RebuildPersistentStoreTests.swift`

**Interfaces:**
- Produces: `RebuildPersistentStore.makeInMemory() throws -> NSPersistentContainer`
- Produces: `RebuildProfileRepository.save(_:)`, `load()`
- Produces: `RebuildProgressRepository.appendIfAbsent(_:) -> Bool`
- Produces: `RebuildMigrationStateRepository.currentVersion`, `markCompleted(version:)`

- [ ] **Step 1: Write failing in-memory repository tests**

```swift
final class RebuildPersistentStoreTests: XCTestCase {
    func testProgressEventIdentityIsIdempotent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(context: container.viewContext)
        let event = RebuildProgressEvent(
            id: "meal:2026-07-25|시금치 나물|oneBite",
            amount: 18,
            occurredAt: Date(timeIntervalSince1970: 1_785_000_000)
        )

        XCTAssertTrue(try repository.appendIfAbsent(event))
        XCTAssertFalse(try repository.appendIfAbsent(event))
        XCTAssertEqual(try repository.totalXP(), 18)
    }
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests"]`.

Expected: FAIL because the persistence types do not exist.

- [ ] **Step 3: Implement the programmatic Core Data model**

Create entities with these unique constraints:

```swift
enum RebuildEntityName {
    static let profile = "RebuildProfile"
    static let mealDay = "RebuildMealDay"
    static let mealRecord = "RebuildMealRecord"
    static let mealPhoto = "RebuildMealPhoto"
    static let progressEvent = "RebuildProgressEvent"
    static let syncEnvelope = "RebuildSyncEnvelope"
    static let parentLink = "RebuildParentLink"
    static let migrationState = "RebuildMigrationState"
}
```

- `RebuildProfile`: unique `id`; role, nickname, officeCode, schoolCode, allergyCodesJSON
- `RebuildMealDay`: unique `date`; payloadJSON, fetchedAt, source
- `RebuildMealRecord`: unique `id`; date, menuName, normalizedMenuName, status, difficultyReasonsJSON, allergyCodesJSON, photoIDsJSON, parentShareEnabled, updatedAt, deletedAt
- `RebuildMealPhoto`: unique `id`; recordID, relativePath, createdAt
- `RebuildProgressEvent`: unique `id`; amount, occurredAt, sourceRecordID
- `RebuildSyncEnvelope`: unique `id`; recordType, recordID, state, retryCount, updatedAt
- `RebuildParentLink`: unique `id`; inviteCode, connectionState, connectedAt
- `RebuildMigrationState`: unique `id`; version, completedAt, sourceDigest

Use `NSPersistentContainer(name:managedObjectModel:)`, `NSMergeByPropertyObjectTrumpMergePolicy`, and an SQLite store named `NaymRebuild.sqlite`. `makeInMemory()` must use `/dev/null`.

- [ ] **Step 4: Run persistence and full iOS tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests"]`.

Expected: PASS.

Run: XcodeBuildMCP `test_sim`.

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Data NaymNaymLevelUpTests/RebuildPersistentStoreTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: add iOS rebuild persistence"
```

### Task 5: iOS 원본 보존형 UserDefaults 이전

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Migration/LegacyDefaultsReader.swift`
- Create: `NaymNaymLevelUp/Rebuild/Migration/RebuildMigrationCoordinator.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests.swift`

**Interfaces:**
- Produces: `LegacyDefaultsReader.readSnapshot() throws -> LegacySnapshot`
- Produces: `RebuildMigrationCoordinator.runIfNeeded(targetVersion: 1) throws -> MigrationOutcome`
- Guarantees: a failed migration does not write completion state or remove legacy keys

- [ ] **Step 1: Write failing migration tests**

```swift
func testMigrationIsIdempotentAndPreservesLegacyDefaults() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    UserProfileStore(defaults: defaults).save(
        UserProfile(
            nickname: "냠냠이",
            schoolName: "냠냠초",
            officeCode: "B10",
            schoolCode: "7010111",
            regionName: "서울",
            selectedAllergyCodes: [1]
        )
    )
    let container = try RebuildPersistentStore.makeInMemory()
    let coordinator = RebuildMigrationCoordinator(defaults: defaults, container: container)

    XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .migrated)
    XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .alreadyCompleted)
    XCTAssertNotNil(UserProfileStore(defaults: defaults).load())
}
```

- [ ] **Step 2: Run the focused migration test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests"]`.

Expected: FAIL because the migration coordinator does not exist.

- [ ] **Step 3: Implement transactional migration**

```swift
enum MigrationOutcome: Equatable {
    case noLegacyData
    case migrated
    case alreadyCompleted
}

struct LegacySnapshot {
    let profile: UserProfile?
    let progress: PlayerProgress
    let mealRecords: [MealRecord]
    let mealPhotoRecords: [MealPhotoRecord]
    let challenges: [ChallengeRecord]
    let parentProfile: ParentProfile
    let childLink: ChildLink?
}
```

Read data only through existing store types. Insert mapped rows in `container.newBackgroundContext().performAndWait`, save once, verify profile count, meal/photo record counts, and XP total, then mark migration version 1. Copy referenced photo files into the rebuild photo directory before saving new relative paths; if a file is missing, preserve its metadata with a missing-file warning. Never call existing store `clear()` methods.

- [ ] **Step 4: Run migration and regression tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests", "-only-testing:NaymNaymLevelUpTests/LocalStoreTests"]`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Migration NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: migrate iOS legacy records safely"
```

### Task 6: Android Kotlin Compose 툴체인과 비활성 새 루트

**Files:**
- Modify: `android/build.gradle`
- Modify: `android/app/build.gradle`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/RebuildActivity.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/foundation/RebuildFeatureGate.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildTheme.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/RebuildFeatureGateTest.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildThemeTest.kt`

**Interfaces:**
- Produces: `RebuildFeatureGate.isEnabled(defaultValue: Boolean, overrideValue: String?)`
- Produces: `RebuildActivity`
- Produces: `RebuildTokens` and `RebuildTheme`
- Guarantees: current Java `MainActivity` remains the launcher while the flag is false

- [ ] **Step 1: Record the pre-Kotlin build baseline**

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: current Java tests and debug build PASS.

- [ ] **Step 2: Enable pinned Kotlin and Compose dependencies**

Add to root plugins:

```groovy
id "org.jetbrains.kotlin.android" version "2.2.21" apply false
id "org.jetbrains.kotlin.plugin.compose" version "2.2.21" apply false
id "org.jetbrains.kotlin.kapt" version "2.2.21" apply false
```

Apply those three plugins in `android/app/build.gradle`, set `buildFeatures { compose true; buildConfig true }`, add `buildConfigField "boolean", "NATIVE_REBUILD_ENABLED", "false"`, and add:

```groovy
compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
}

kotlinOptions {
    jvmTarget = "17"
}

defaultConfig {
    testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
}

def composeBom = platform("androidx.compose:compose-bom:2025.12.01")
implementation composeBom
androidTestImplementation composeBom
implementation "androidx.activity:activity-compose:1.13.0"
implementation "androidx.compose.material3:material3"
implementation "androidx.compose.ui:ui"
implementation "androidx.compose.ui:ui-tooling-preview"
implementation "androidx.lifecycle:lifecycle-runtime-compose:2.10.0"
implementation "androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0"
implementation "androidx.navigation:navigation-compose:2.9.8"
debugImplementation "androidx.compose.ui:ui-tooling"
androidTestImplementation "androidx.compose.ui:ui-test-junit4"
debugImplementation "androidx.compose.ui:ui-test-manifest"
androidTestImplementation "androidx.test:runner:1.7.0"
androidTestImplementation "androidx.test.ext:junit:1.3.0"
```

- [ ] **Step 3: Write failing gate and theme tests**

```kotlin
class RebuildFeatureGateTest {
    @Test fun defaultsToBuildConfigValue() {
        assertFalse(RebuildFeatureGate.isEnabled(false, null))
    }

    @Test fun explicitTrueOverrideWins() {
        assertTrue(RebuildFeatureGate.isEnabled(false, "true"))
    }
}
```

```kotlin
class RebuildThemeTest {
    @Test fun approvedTokensAreExact() {
        assertEquals(48, RebuildTokens.minimumActionSize)
        assertEquals(listOf(4, 8, 12, 16, 24, 32), RebuildTokens.spacing)
        assertEquals(0xFF1F5E43, RebuildTokens.Forest700)
        assertEquals(0xFFFFF9EC, RebuildTokens.Cream50)
    }
}
```

- [ ] **Step 4: Run tests and verify missing-type failures**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*RebuildFeatureGateTest' --tests '*RebuildThemeTest'`

Expected: FAIL because gate and theme types do not exist.

- [ ] **Step 5: Implement the gate, theme, and Compose root**

Implement `RebuildFeatureGate`, a `ComponentActivity` that calls `setContent { RebuildApp() }`, and a temporary Compose role chooser with 48dp minimum controls. Register `.rebuild.RebuildActivity` as non-exported.

Map `design-tokens.json` to `RebuildTokens` and `RebuildTheme`. Use Material typography with the system sans family and scalable `sp`; do not add a bundled body font or dynamic device colors.

At the start of `MainActivity.onCreate`, launch `RebuildActivity` and finish only when `BuildConfig.NATIVE_REBUILD_ENABLED` is true. Do not read a user-controlled deep-link extra for this release gate.

- [ ] **Step 6: Run Android unit tests and debug build**

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: all unit tests PASS and debug APK builds while the legacy launcher remains active.

- [ ] **Step 7: Commit**

```bash
git add android/build.gradle android/app/build.gradle android/app/src/main/AndroidManifest.xml android/app/src/main/java android/app/src/test
git commit -m "feat: add disabled Android Compose root"
```

### Task 7: Android Room 모델과 저장소

**Files:**
- Modify: `android/app/build.gradle`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildEntities.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDao.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDatabase.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildRepositories.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDatabaseTest.kt`

**Interfaces:**
- Produces: Room database `naym-rebuild.db`, schema version 1
- Produces: `ProfileDao`, `MealDayDao`, `MealRecordDao`, `MealPhotoDao`, `ProgressDao`, `SyncEnvelopeDao`, `ParentLinkDao`, `MigrationStateDao`
- Produces: `ProgressRepository.appendIfAbsent(event): Boolean`
- Produces: `ProgressRepository.totalXp(): Int`
- Produces: `MigrationStateRepository.markCompleted(version, sourceDigest)`

- [ ] **Step 1: Add Room test dependencies and failing test**

Add:

```groovy
implementation "androidx.room:room-runtime:2.8.4"
implementation "androidx.room:room-ktx:2.8.4"
kapt "androidx.room:room-compiler:2.8.4"
androidTestImplementation "androidx.room:room-testing:2.8.4"
androidTestImplementation "androidx.test.ext:junit:1.3.0"
```

Write an in-memory instrumentation test that inserts the same progress event twice and expects `18` total XP.

- [ ] **Step 2: Run the focused instrumentation test**

Run: `cd android && ./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabaseTest`

Expected: FAIL because the database types do not exist.

- [ ] **Step 3: Implement Room entities, DAO, and repositories**

Use exact primary keys matching the iOS model:

```kotlin
@Entity(tableName = "progress_events")
data class ProgressEventEntity(
    @PrimaryKey val id: String,
    val amount: Int,
    val occurredAtEpochMillis: Long,
    val sourceRecordId: String?
)

@Dao
interface ProgressDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(event: ProgressEventEntity): Long

    @Query("SELECT COALESCE(SUM(amount), 0) FROM progress_events")
    suspend fun totalXp(): Int
}
```

Add matching tables and named DAO interfaces for profiles, meal days, meal records, meal photos, sync envelopes, parent links, and migration state. Meal records include difficulty reasons, allergy codes, photo IDs, and parent sharing state. `MealDayDao` must expose `observe(date): Flow<MealDayEntity?>` and `upsert`; `SyncEnvelopeDao` must expose ordered batches by `updatedAt`; `MigrationStateDao` must expose version lookup and insert. Export schema JSON to `android/app/schemas`.

- [ ] **Step 4: Run database tests and build**

Run: `cd android && ./gradlew connectedDebugAndroidTest testDebugUnitTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle android/app/schemas android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data android/app/src/androidTest
git commit -m "feat: add Android rebuild persistence"
```

### Task 8: Android 원본 보존형 SharedPreferences 이전

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/migration/LegacyPreferencesReader.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/migration/RebuildMigrationCoordinator.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/migration/RebuildMigrationCoordinatorTest.kt`

**Interfaces:**
- Produces: `LegacyPreferencesReader.readSnapshot(): LegacySnapshot`
- Produces: `RebuildMigrationCoordinator.runIfNeeded(1): MigrationOutcome`
- Guarantees: a failed migration leaves `naymnaym-android` unchanged

- [ ] **Step 1: Write the failing coordinator test with fakes**

```kotlin
@Test fun migrationIsIdempotentAndDoesNotClearLegacySource() = runTest {
    val source = FakeLegacySource(profileJson = """{"nickname":"냠냠이"}""")
    val target = FakeMigrationTarget()
    val coordinator = RebuildMigrationCoordinator(source, target)

    assertEquals(MigrationOutcome.Migrated, coordinator.runIfNeeded(1))
    assertEquals(MigrationOutcome.AlreadyCompleted, coordinator.runIfNeeded(1))
    assertEquals("""{"nickname":"냠냠이"}""", source.profileJson)
}
```

- [ ] **Step 2: Run the focused JVM test**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*RebuildMigrationCoordinatorTest'`

Expected: FAIL because migration interfaces do not exist.

- [ ] **Step 3: Implement reader, target adapter, and transaction**

```kotlin
enum class MigrationOutcome { NoLegacyData, Migrated, AlreadyCompleted }

data class LegacySnapshot(
    val profileJson: String?,
    val progressJson: String?,
    val mealsJson: String?,
    val mealPhotosJson: String?,
    val challengesJson: String?,
    val parentJson: String?,
    val childLinkJson: String?
)
```

Read the existing preference file name `naymnaym-android`. Use `RebuildDatabase.withTransaction`, verify inserted profile and XP counts, then insert migration state version 1. Do not call `SharedPreferences.edit().clear()` or remove legacy keys.

- [ ] **Step 4: Run all Android tests and contract validation**

Run: `python3 scripts/validate-native-rebuild-contracts.py`

Expected: exit 0.

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/migration android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/migration
git commit -m "feat: migrate Android legacy records safely"
```

### Task 9: 기반 단계 통합 검증

**Files:**
- Modify: `README.md`
- Create: `docs/architecture/native-rebuild-foundation.md`

**Interfaces:**
- Documents: feature flag activation commands for local debug only
- Documents: database names, schema version 1, migration source keys

- [ ] **Step 1: Document exact local activation without changing defaults**

Add:

```text
iOS Simulator launch argument:
-native-rebuild-enabled YES

Android local source edit for a debug-only verification:
BuildConfig.NATIVE_REBUILD_ENABLED remains false in committed code.
Use an uncommitted debug buildConfigField override, verify RebuildActivity, then revert it.
```

Document `NaymRebuild.sqlite`, `naym-rebuild.db`, migration version 1, and the requirement that source records remain untouched.

- [ ] **Step 2: Run the complete foundation gate**

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Expected: PASS.

Run: XcodeBuildMCP `test_sim`.

Expected: PASS.

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: PASS.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 3: Confirm the release gates remain disabled**

Run: `rg -n 'native-rebuild-enabled|NATIVE_REBUILD_ENABLED' NaymNaymLevelUp android/app`

Expected: iOS defaults to `false`; Android committed `buildConfigField` is `false`.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/architecture/native-rebuild-foundation.md
git commit -m "docs: record native rebuild foundation"
```
