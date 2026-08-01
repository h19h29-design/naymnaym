# 급식레벨업 1.2 도감·급식표 릴리스 준비 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 1.2 변경을 보존하면서 iOS·Android 도감을 14단계 캐릭터와 36개 안전한 식사 배지로 확장하고, 선택일 영양정보와 릴리스 후보를 완성한다.

**Architecture:** 공통 JSON 계약이 14단계 성장과 배지 정의를 소유한다. 두 플랫폼의 순수 `CollectionProgress` 계산기가 로컬 식사 기록을 같은 결과로 변환하고, 화면은 그 결과와 선택일 급식만 렌더링한다. Figma에는 같은 토큰과 아트 원본을 보관한다.

**Tech Stack:** SwiftUI/XCTest/Core Data, Kotlin/Jetpack Compose/JUnit/Room, JSON contracts, Figma, xcodebuild, Gradle.

## Global Constraints

- 기존 미커밋 iOS `1.2 (33)` 및 Android `1.2 (13)` 변경을 보존한다.
- `oneBite`, `half`, `finished`만 긍정 섭취다. 알레르기 회피·어려움 기록은 섭취 배지에 포함하지 않는다.
- 광고·추적·로그인·결제 SDK를 추가하지 않는다.
- 행동 변경은 iOS·Android에서 RED → GREEN 테스트를 먼저 수행한다.
- 스토어 업로드는 별도 명시 요청 없이는 수행하지 않는다.

---

### Task 1: 공통 14단계 성장 계약을 확장한다

**Files:**

- Modify: `contracts/native-rebuild/v1/growth-policy.json`
- Modify: `NaymNaymLevelUp/Resources/RebuildContracts/growth-policy.json`
- Modify: `android/app/src/main/assets/rebuild-contracts/growth-policy.json`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthDomain.kt`
- Test: `NaymNaymLevelUpTests/GrowthPolicyTests.swift`
- Test: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthPolicyTest.kt`

**Interfaces:**

```swift
// Must accept 2...14 aligned entries, retaining all existing validation.
let policy = try GrowthPolicy(data: contract)
let level = policy.level(totalXP: 4_850) // 14
```

```kotlin
val policy = GrowthPolicy.decode(contract)
val level = policy.level(4_850) // 14
```

- [ ] **Step 1: Write failing boundary tests.** Add `1_399 → 7`, `1_400 → 8`, `4_149 → 12`, `4_150 → 13`, `4_849 → 13`, `4_850 → 14`, and all 14 titles/thresholds.
- [ ] **Step 2: Verify RED.** Run iOS `GrowthPolicyTests` and Android `*GrowthPolicyTest`; both must fail because the seven-entry guard rejects or clamps stage 8.
- [ ] **Step 3: Implement the 14 entry contract.** Copy the exact rows from `docs/superpowers/specs/2026-08-01-collection-v12-design.md`; replace only the fixed `== 7` cardinality with `2...14` / `2..14` while keeping strict order and unique nonblank names.
- [ ] **Step 4: Verify GREEN.** Re-run both focused tests; malformed duplicate threshold input must still fail.
- [ ] **Step 5: Commit.** Stage the three JSON copies, two domains, and two tests with `git commit -m "feat: expand growth policy to fourteen stages"`.

### Task 2: 공통 배지 계약과 순수 계산기를 만든다

**Files:**

- Create: `contracts/native-rebuild/v1/collection-policy.json`
- Create: `NaymNaymLevelUp/Resources/RebuildContracts/collection-policy.json`
- Create: `android/app/src/main/assets/rebuild-contracts/collection-policy.json`
- Create: `NaymNaymLevelUp/Rebuild/Growth/CollectionProgress.swift`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/CollectionProgress.kt`
- Test: `NaymNaymLevelUpTests/CollectionProgressTests.swift`
- Test: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth/CollectionProgressTest.kt`

**Interfaces:**

```swift
struct CollectionRecord: Equatable, Sendable {
    let date: String
    let normalizedMenuName: String
    let status: String
}

let progress = try CollectionProgress.evaluate(
    totalXP: 500,
    records: records,
    policyData: contract
)
```

```kotlin
data class CollectionRecord(
    val date: String,
    val normalizedMenuName: String,
    val status: String,
)

val progress = CollectionProgress.evaluate(500, records, contract)
```

- [ ] **Step 1: Write failing tests.** Use weekday fixtures with vegetable, protein, dairy, fruit, one-bite, finished, allergy, and difficult statuses. Assert first badges in all categories, 3-menu day, active-day count, and weekend-tolerant streak; assert allergy/difficult records do not increase food counters.
- [ ] **Step 2: Verify RED.** Run only `CollectionProgressTests` / `*CollectionProgressTest`; tests must fail because policy and evaluator do not exist.
- [ ] **Step 3: Implement the policy and metrics.** Encode the approved 3×12 ordered badges and Korean food-group keyword arrays. Derive positive count, one-bite count, finished count, distinct menu count, food-group counts, 3-menu active days, active dates, and weekday streak without mutating persistence.
- [ ] **Step 4: Verify GREEN.** Re-run both focused tests and compare earned identifiers/counts exactly.
- [ ] **Step 5: Commit.** Stage all policy copies, evaluators, and tests with `git commit -m "feat: add collection badge policy"`.

### Task 3: 도감용 저장소 스냅샷을 추가한다

**Files:**

- Modify: `NaymNaymLevelUp/Rebuild/Data/RebuildRepositories.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDao.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthDomain.kt`
- Test: `NaymNaymLevelUpTests/GrowthRepositoryTests.swift`
- Test: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthRepositoryTest.kt`

**Interfaces:**

```swift
protocol CollectionSnapshotProviding {
    func loadCollection() async throws -> CollectionSnapshot
}
```

```kotlin
interface CollectionSnapshotSource {
    suspend fun loadCollection(): CollectionSnapshot
}
```

- [ ] **Step 1: Write failing repository tests.** Insert active and deleted meal records, then assert only active `(date, normalizedMenuName, status)` values are returned and total XP remains unchanged.
- [ ] **Step 2: Verify RED.** Run focused iOS/Android growth repository tests; they must fail for the missing collection snapshot API.
- [ ] **Step 3: Implement deterministic active-record reads.** Core Data fetches `deletedAt == nil` ordered `date`, `normalizedMenuName`, `id`; Room adds the equivalent query. Keep timeline `recentPositiveEvents(limit:)` behavior unchanged.
- [ ] **Step 4: Verify GREEN.** Re-run the tests; deleted records must never unlock badges.
- [ ] **Step 5: Commit.** Commit repository, DAO, domain, and test files with `feat: load active meal records for collection progress`.

### Task 4: A안 오늘·도감·설정 탭을 구현한다

**Files:**

- Modify: `NaymNaymLevelUp/Rebuild/Child/ChildNavigationView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/CollectionView.swift`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildNavigation.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/CollectionScreen.kt`
- Test: `NaymNaymLevelUpTests/CollectionViewTests.swift`
- Test: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthScreenTest.kt`

**Interfaces:**

```swift
// Collection screen consumes the snapshot from Task 3, not just total XP.
CollectionView(snapshotProvider: provider, policy: growthPolicy, isActive: true)
```

```kotlin
CollectionScreen(repository = repository, policy = policy)
```

- [ ] **Step 1: Write failing UI behavior tests.** Assert five child navigation labels, combined character-hub identifier, 14 character card identifiers, four category tabs, and a locked badge identifier. Keep controls at least 48pt/dp.
- [ ] **Step 2: Verify RED.** Run the iOS focused UI/unit target and Android `GrowthScreenTest`; missing settings/category behavior must fail.
- [ ] **Step 3: Implement the A layout.** Combine character art, message, level, total XP, and next progress in one forest-backed card. Render the 14-card character grid and three 12-badge grids. Use `SettingsView`/existing Android settings route rather than duplicating settings content.
- [ ] **Step 4: Verify GREEN.** Re-run focus tests and inspect iPhone 17/SE plus Compose test tags for clipped labels and locked states.
- [ ] **Step 5: Commit.** Commit all touched screens/tests with `feat: add categorized collection experience`.

### Task 5: 주간·월간 선택일 영양정보를 구현한다

**Files:**

- Modify: `NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealScheduleScreen.kt`
- Create: `NaymNaymLevelUpTests/MealScheduleSelectionTests.swift`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/child/MealScheduleSelectionTest.kt`

**Interfaces:**

```swift
// Both period layouts pass exactly one selected meal into the footer.
nutritionSummary(meals: selectedMeal.map { [$0] } ?? [])
```

```kotlin
NutritionSummary(selectedMeal?.let(::listOf).orEmpty())
```

- [ ] **Step 1: Write failing selection tests.** Use two dates with distinct nutrition/allergies and one empty date. Assert weekly header/cell and monthly cell changes replace values rather than averaging; empty date exposes `해당 날짜의 영양 정보가 없어요.`.
- [ ] **Step 2: Verify RED.** Run the two focused selection tests; current period averages must make them fail.
- [ ] **Step 3: Implement selection wiring.** Make weekly headers and menu cells interactive, retain monthly selection, and feed only `meal(for: selectedDate)` to nutrition and allergy summaries. Do not alter loading or invent meals.
- [ ] **Step 4: Verify GREEN.** Re-run focused tests; selection must be deterministic on both platforms.
- [ ] **Step 5: Commit.** Commit screen/test files with `feat: show nutrition for selected schedule date`.

### Task 6: Figma 원본 라이브러리와 적용 화면을 생성한다

**Files:**

- External: Figma file `PzhrBaw0BuAMNTX4BPyfsM`
- Create: `docs/qa/collection-v12-figma-record.md`

- [ ] **Step 1: Create Figma foundations.** Create `급식레벨업/Rebuild` Default variables for eight Rebuild colors, white, spacing, radii, and action size; then create Noto Sans KR Title/Section/Body/Caption styles. Capture metadata and a screenshot.
- [ ] **Step 2: Create validated components.** Create `Collection/Tab`, `Collection/Character Card`, `Collection/Badge Tile`, and `Collection/Progress` sequentially. Validate each set with Figma metadata plus screenshot before the next component.
- [ ] **Step 3: Place source art and compositions.** Preserve existing character 1–7 art; add 8–14 and 36 badge originals under `Artwork`; compose the A 도감, compact home hub, and selected-date schedule examples.
- [ ] **Step 4: Record evidence.** Write page URL, node IDs, 14-character/36-badge counts, and screenshot observations in `docs/qa/collection-v12-figma-record.md`.
- [ ] **Step 5: Commit.** Commit the evidence record with `docs: record 1.2 collection Figma library`.

### Task 7: 1.2 릴리스 후보를 만들고 검증한다

**Files:**

- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Modify: `android/app/build.gradle`
- Create: `release/ReleaseStatus/collection-v12-readiness.md`

- [ ] **Step 1: Preserve version metadata.** Keep `MARKETING_VERSION=1.2`, `CURRENT_PROJECT_VERSION=33`, `versionName "1.2"`, and `versionCode 13`; include their evidence in the readiness record.
- [ ] **Step 2: Run full builds.** Run `xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -destination 'platform=iOS Simulator,name=iPhone 17'` and `cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:bundleRelease --no-daemon`.
- [ ] **Step 3: Run release gates.** Run `bash scripts/verify-release-readiness.sh` and `bash scripts/verify-native-rebuild-contracts.sh`; record command, exit status, simulator/emulator target, archive/export state, and AAB path. Do not claim an upload.
- [ ] **Step 4: Commit and push.** Stage the two existing version files plus readiness evidence, commit `release: prepare 1.2 collection candidate`, then run `git push origin codex/android-closed-test-v12`.
