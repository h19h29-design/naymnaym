# 냠냠레벨업 아이 급식 핵심 순환 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이가 오늘 급식을 확인하고 먹은 상태를 기록하면, 놓칠 수 있는 영양소와 대체 음식을 확인하고 캐릭터 XP 보상을 받는 오프라인 우선 흐름을 양 플랫폼에 만든다.

**Architecture:** 급식 조회 결과는 로컬 데이터베이스에 캐시하고 UI는 캐시를 관찰한다. 식사 기록과 XP 이벤트는 하나의 로컬 트랜잭션으로 저장하며, 플랫폼 중립 영양·XP 계약과 테스트 벡터로 Swift와 Kotlin 결과를 일치시킨다.

**Tech Stack:** SwiftUI, Core Data, URLSession, XCTest, Kotlin, Compose, Room, Coroutines/Flow, JUnit

## Global Constraints

- 기반 계획 `2026-07-25-native-rebuild-foundation-implementation.md`가 완료되어 있어야 한다.
- 새 UI는 `native-rebuild-enabled` 플래그 뒤에서만 보인다.
- 새 UI에서 기록 가능한 상태는 `finished`, `oneBite`, `smelledOnly`, `difficultToday`, `allergyAvoided`다.
- 이전 기록의 `half` 상태는 읽기·이전 호환을 위해 유지하지만 새 기록 행동으로 노출하지 않는다.
- 먹지 않음, 알레르기 회피, 기록 누락으로 XP를 차감하지 않는다.
- 하루 기본 XP 50, 도전 보너스 70, 전체 XP 100 상한을 유지한다.
- 알레르기 위험 메뉴에서는 먹기 권유보다 안전 안내를 먼저 표시한다.
- 영양 문구에는 `놓칠 수 있어요`와 `교육용 참고` 의미를 유지한다.

## Target File Map

### 공통 계약

- `contracts/native-rebuild/v1/nutrition-rules.json`: 키워드별 영양소와 대체 음식
- `contracts/native-rebuild/v1/xp-policy.json`: 상태별 XP와 하루 상한
- `contracts/native-rebuild/v1/meal-loop-fixtures.json`: 영양·XP·중복 기록 테스트 벡터

### iOS

- `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`: 새 급식 도메인 값
- `NaymNaymLevelUp/Rebuild/Meal/RebuildMealClient.swift`: NEIS 요청과 파싱
- `NaymNaymLevelUp/Rebuild/Meal/RebuildMealRepository.swift`: 캐시 우선 조회
- `NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift`: JSON 규칙 평가
- `NaymNaymLevelUp/Rebuild/Meal/RecordMealUseCase.swift`: 기록·XP 원자 처리
- `NaymNaymLevelUp/Rebuild/Onboarding/*`: 역할·프로필·학교·알레르기 설정
- `NaymNaymLevelUp/Rebuild/Child/ChildNavigationView.swift`: `오늘 · 성장 · 도감`
- `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`: 오늘 장면
- `NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift`: 메뉴별 기록

### Android

- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/MealDomain.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/NeisMealClient.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/MealRepository.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/NutritionRuleEngine.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/RecordMealUseCase.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/*`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildNavigation.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealRecordingSheet.kt`

---

### Task 1: 영양 규칙과 XP 정책을 공통 계약으로 고정

**Files:**
- Create: `contracts/native-rebuild/v1/nutrition-rules.json`
- Create: `contracts/native-rebuild/v1/xp-policy.json`
- Create: `contracts/native-rebuild/v1/meal-loop-fixtures.json`
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `scripts/tests/test_native_rebuild_contracts.py`

**Interfaces:**
- Produces: ordered keyword rules returning unique nutrient IDs
- Produces: status XP `finished=10`, `half=12`, `oneBite=18`, `smelledOnly=10`, `difficultToday=3`, `allergyAvoided=8`
- Produces: `dailyBaseCap=50`, `dailyChallengeBonusCap=70`, `dailyTotalCap=100`

- [ ] **Step 1: Add failing assertions for nutrition and XP**

```python
def test_xp_policy_preserves_existing_values(self):
    policy = json.loads((ROOT / "contracts/native-rebuild/v1/xp-policy.json").read_text())
    self.assertEqual(policy["statusXP"]["oneBite"], 18)
    self.assertEqual(policy["statusXP"]["allergyAvoided"], 8)
    self.assertEqual(policy["caps"], {"base": 50, "challengeBonus": 70, "total": 100})

def test_nutrition_fixture_is_deterministic(self):
    fixtures = json.loads((ROOT / "contracts/native-rebuild/v1/meal-loop-fixtures.json").read_text())
    spinach = next(item for item in fixtures["nutrition"] if item["menuName"] == "시금치나물")
    self.assertEqual(spinach["nutrients"], ["fiber", "vitamin"])
```

- [ ] **Step 2: Run the tests and verify missing-file failures**

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Expected: FAIL for the three missing JSON files.

- [ ] **Step 3: Create exact policy files**

`nutrition-rules.json` must port every keyword from `NutritionEstimator.estimateNutrients` and add one or two familiar alternatives per nutrient:

```json
{
  "version": 1,
  "nutrients": {
    "fiber": {"childName": "식이섬유", "alternatives": ["사과", "고구마"]},
    "vitamin": {"childName": "비타민", "alternatives": ["귤", "토마토"]},
    "protein": {"childName": "단백질", "alternatives": ["달걀", "두부"]},
    "iron": {"childName": "철분", "alternatives": ["소고기", "두부"]},
    "calcium": {"childName": "칼슘", "alternatives": ["우유", "멸치"]},
    "carbohydrate": {"childName": "탄수화물", "alternatives": ["밥", "고구마"]}
  }
}
```

`meal-loop-fixtures.json` must cover `시금치나물`, `닭고기`, `우유`, `현미밥`, 알 수 없는 메뉴, 하루 상한 직전 기록, 중복 이벤트 ID를 포함한다.

- [ ] **Step 4: Validate all contract files**

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Expected: `native-rebuild-contract-sync: PASS`.

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add contracts/native-rebuild scripts/validate-native-rebuild-contracts.py scripts/tests/test_native_rebuild_contracts.py NaymNaymLevelUp/Resources/RebuildContracts android/app/src/main/assets/rebuild-contracts
git commit -m "feat: define shared meal and XP rules"
```

### Task 2: iOS 캐시 우선 급식 저장소

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`
- Create: `NaymNaymLevelUp/Rebuild/Meal/RebuildMealClient.swift`
- Create: `NaymNaymLevelUp/Rebuild/Meal/RebuildMealRepository.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/RebuildMealRepositoryTests.swift`

**Interfaces:**
- Produces: `RebuildMealRepository.observe(date:) -> AsyncStream<MealLoadState>`
- Produces: `RebuildMealRepository.refresh(date:school:) async`
- Produces: `MealLoadState.cached`, `.refreshing`, `.live`, `.empty`, `.failed`

- [ ] **Step 1: Write a failing cache-fallback test**

```swift
func testRefreshFailureKeepsCachedMealVisible() async throws {
    let cache = InMemoryMealDayStore(meals: [.fixture(date: "2026-07-25")])
    let client = StubMealClient(result: .failure(NEISClientError.serverStatus(503)))
    let repository = RebuildMealRepository(store: cache, client: client)

    await repository.refresh(date: "2026-07-25", school: .fixture)

    XCTAssertEqual(await repository.currentState(date: "2026-07-25"), .cached(.fixture(date: "2026-07-25"), refreshedAt: nil))
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildMealRepositoryTests"]`.

Expected: FAIL because the repository does not exist.

- [ ] **Step 3: Implement injected client, parser, and cache**

```swift
protocol RebuildMealClientProtocol {
    func fetch(date: String, school: RebuildSchool) async throws -> RebuildMealDay?
}

enum MealLoadState: Equatable {
    case cached(RebuildMealDay, refreshedAt: Date?)
    case refreshing(RebuildMealDay?)
    case live(RebuildMealDay)
    case empty
    case failed(message: String, cached: RebuildMealDay?)
}
```

Use the current NEIS endpoint and redact `KEY` in debug logs. Store successful payloads in `RebuildMealDay`; do not replace a cached meal when a network request fails.

- [ ] **Step 4: Run repository and existing parser tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildMealRepositoryTests", "-only-testing:NaymNaymLevelUpTests/MealParserTests"]`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Meal NaymNaymLevelUpTests/RebuildMealRepositoryTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: add cached iOS meal repository"
```

### Task 3: Android 캐시 우선 급식 저장소

**Files:**
- Modify: `android/app/build.gradle`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/MealDomain.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/NeisMealClient.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/MealRepository.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/meal/MealRepositoryTest.kt`

**Interfaces:**
- Produces: `MealRepository.observe(date: LocalDate): Flow<MealLoadState>`
- Produces: `suspend MealRepository.refresh(date, school)`
- Consumes: `MealDayDao` from the foundation database

- [ ] **Step 1: Add test dependencies and write the failing test**

Add `org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2` and use:

```kotlin
@Test fun refreshFailureKeepsCachedMealVisible() = runTest {
    val store = FakeMealDayStore(listOf(MealDay.fixture("2026-07-25")))
    val client = FakeMealClient(Result.failure(IOException("offline")))
    val repository = MealRepository(store, client, backgroundScope)

    repository.refresh(LocalDate.parse("2026-07-25"), School.fixture)

    assertEquals(MealLoadState.Cached(MealDay.fixture("2026-07-25"), null), repository.currentState("2026-07-25"))
}
```

- [ ] **Step 2: Run the focused JVM test**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*MealRepositoryTest'`

Expected: FAIL because the meal package does not exist.

- [ ] **Step 3: Implement the Kotlin client and repository**

Use `HttpURLConnection` behind this injectable interface to avoid adding a tracking-capable networking SDK:

```kotlin
fun interface NeisTransport {
    suspend fun get(url: URL): ByteArray
}

sealed interface MealLoadState {
    data class Cached(val meal: MealDay, val refreshedAt: Instant?) : MealLoadState
    data class Refreshing(val cached: MealDay?) : MealLoadState
    data class Live(val meal: MealDay) : MealLoadState
    data object Empty : MealLoadState
    data class Failed(val message: String, val cached: MealDay?) : MealLoadState
}
```

Mirror the iOS cache replacement rules and strip HTML line breaks from `DDISH_NM`.

- [ ] **Step 4: Run focused and full Android tests**

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/meal
git commit -m "feat: add cached Android meal repository"
```

### Task 4: 양 플랫폼의 영양 규칙과 멱등 기록 사용 사례

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift`
- Create: `NaymNaymLevelUp/Rebuild/Meal/RecordMealUseCase.swift`
- Create: `NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests.swift`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/NutritionRuleEngine.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal/RecordMealUseCase.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/meal/RecordMealUseCaseTest.kt`

**Interfaces:**
- Produces: `NutritionRuleEngine.insight(menuName:) -> NutritionInsight`
- Produces: `RecordMealUseCase.execute(command) -> RecordMealResult`
- Guarantees: repeated `progressEventIdentity` returns `xpGranted = 0`

- [ ] **Step 1: Write equivalent Swift and Kotlin failing tests**

Use the same fixture:

```text
date=2026-07-25
menuName=시금치나물
status=oneBite
expected nutrients=fiber,vitamin
first xpGranted=18
second xpGranted=0
motion=mealSuccess
```

Swift assertion:

```swift
XCTAssertEqual(first, RecordMealResult(xpGranted: 18, totalXP: 18, motion: .mealSuccess))
XCTAssertEqual(second.xpGranted, 0)
```

Kotlin assertion:

```kotlin
assertEquals(RecordMealResult(18, 18, MotionState.MealSuccess), first)
assertEquals(0, second.xpGranted)
```

- [ ] **Step 2: Verify both focused tests fail**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"]`.

Run: `cd android && ./gradlew testDebugUnitTest --tests '*RecordMealUseCaseTest'`

Expected: both FAIL because engines and use cases do not exist.

- [ ] **Step 3: Implement exact command/result types and transactions**

```swift
struct RecordMealCommand: Equatable {
    let recordID: String
    let date: String
    let menuName: String
    let status: RebuildEatingStatus
    let difficultyReasons: [RebuildDifficultyReason]
    let allergyCodes: [Int]
    let photoIDs: [String]
    let parentShareEnabled: Bool
    let occurredAt: Date
}

struct RecordMealResult: Equatable {
    let xpGranted: Int
    let totalXP: Int
    let motion: RebuildMotionState
}
```

Kotlin uses the same field names in camelCase. Calculate XP from `xp-policy.json`, apply daily caps, write meal record and progress event in one Core Data background-context save or Room `withTransaction`.

- [ ] **Step 4: Run contract and platform tests**

Run: `python3 scripts/tests/test_native_rebuild_contracts.py`

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"]`.

Run: `cd android && ./gradlew testDebugUnitTest --tests '*RecordMealUseCaseTest'`

Expected: all PASS with identical fixture results.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Meal NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests.swift android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/meal android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/meal
git commit -m "feat: record meals with shared XP semantics"
```

### Task 5: 신규 사용자 프로필·학교·알레르기 온보딩

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildOnboardingDomain.swift`
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildOnboardingViewModel.swift`
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildOnboardingFlowView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildSchoolSearchView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildAllergySelectionView.swift`
- Create: `NaymNaymLevelUpTests/RebuildOnboardingViewModelTests.swift`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/OnboardingDomain.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/OnboardingViewModel.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/OnboardingFlow.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/SchoolSearchScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/AllergySelectionScreen.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/OnboardingViewModelTest.kt`
- Modify: both rebuild root files

**Interfaces:**
- Produces steps: `role`, `nickname`, `school`, `allergies`, `confirmation`
- Produces: `OnboardingDraft(role,nickname,school,allergyCodes)`
- Produces: `complete() -> RebuildUserProfile`
- Consumes: existing NEIS school search endpoint through an injected search client

- [ ] **Step 1: Write matched failing state-machine tests**

Shared scenario:

```text
child role
nickname=냠냠이
school=서울 냠냠초, officeCode=B10, schoolCode=7010111
allergies=1,5
expected next destination=today
```

Swift:

```swift
XCTAssertEqual(viewModel.step, .role)
viewModel.selectRole(.child)
viewModel.setNickname(" 냠냠이 ")
viewModel.selectSchool(.fixture)
viewModel.setAllergies([1, 5])
let profile = try await viewModel.complete()
XCTAssertEqual(profile.nickname, "냠냠이")
XCTAssertEqual(profile.allergyCodes, [1, 5])
```

Kotlin performs the same assertions with `runTest`.

- [ ] **Step 2: Run focused tests on both platforms**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/RebuildOnboardingViewModelTests"]`.

Run: `cd android && ./gradlew testDebugUnitTest --tests '*OnboardingViewModelTest'`

Expected: both FAIL because onboarding types do not exist.

- [ ] **Step 3: Implement the state machine and profile transaction**

Validation rules:

- trimmed nickname length 1–12 grapheme clusters
- child role requires office and school code
- parent role skips school/allergies and routes to parent connection
- allergy codes are unique, sorted integers
- completion saves one profile transaction; cancel leaves no partial profile

School search debounces 300ms, shows cached sample schools only when explicitly in demo mode, and distinguishes no result from network failure.

- [ ] **Step 4: Implement accessible platform flows**

Use one question per screen, system-scalable text, 48pt/dp actions, visible progress text such as `2/5`, and a final confirmation that repeats school and allergies. Do not request birth date, exact address, photo, or location.

- [ ] **Step 5: Run full tests**

Run: XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Onboarding NaymNaymLevelUpTests/RebuildOnboardingViewModelTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/onboarding
git commit -m "feat: add native rebuild onboarding"
```

### Task 6: iOS `오늘` 숲 장면과 기록 흐름

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Child/ChildNavigationView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/TodayForestViewModel.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/TodayForestViewModelTests.swift`

**Interfaces:**
- Produces: tabs `today`, `growth`, `collection`
- Produces: one primary action `오늘 급식 기록하기`
- Consumes: `RebuildMealRepository`, `RecordMealUseCase`

- [ ] **Step 1: Write failing ViewModel state tests**

```swift
func testCachedMealKeepsPrimaryActionAvailableOffline() async {
    let viewModel = TodayForestViewModel(repository: .cachedFixture, recorder: .fixture)
    await viewModel.load()
    XCTAssertEqual(viewModel.title, "오늘 급식")
    XCTAssertEqual(viewModel.primaryActionTitle, "오늘 급식 기록하기")
    XCTAssertTrue(viewModel.isPrimaryActionEnabled)
    XCTAssertEqual(viewModel.sourceLabel, "저장된 급식")
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/TodayForestViewModelTests"]`.

Expected: FAIL because the ViewModel does not exist.

- [ ] **Step 3: Implement views with the approved hierarchy**

`TodayForestView` order:

1. accessible title and date
2. current character slot
3. meal summary with source label
4. one full-width primary action
5. compact current progress

`MealRecordingSheet` shows each menu name and the five active statuses. Allergy-risk items initially expose `안전하게 피했어요` and `보호자와 확인하기`; `한입도전` is disabled. Every actionable control has a minimum 48pt height and a full accessibility label.

When the child chooses `오늘은 어려워요`, open a second step for the existing reasons `냄새`, `식감`, `맛`, `모양`, `기타`; store a unique ordered array. `냄새만 맡아봤어요` and `안전하게 피했어요` may skip the reason step. Preserve photo metadata migrated from the old app, but do not require a photo to finish a record.

- [ ] **Step 4: Run unit tests and inspect on two simulators**

Run: XcodeBuildMCP `test_sim`.

Expected: PASS.

Run the flagged UI on iPhone 17 Pro Max and an available compact iPhone simulator. Verify default and accessibility-extra-extra-extra-large text without truncated menu names.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Child NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift NaymNaymLevelUpTests/TodayForestViewModelTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: build iOS child meal loop"
```

### Task 7: Android `오늘` 숲 장면과 기록 흐름

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildNavigation.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealRecordingSheet.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestViewModel.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestViewModelTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreenTest.kt`

**Interfaces:**
- Produces: routes `today`, `growth`, `collection`
- Produces: Compose test tags `today_primary_action`, `meal_item_{index}`, `status_{status}`
- Consumes: Android `MealRepository`, `RecordMealUseCase`

- [ ] **Step 1: Write failing ViewModel and Compose semantics tests**

```kotlin
@Test fun cachedMealKeepsPrimaryActionAvailableOffline() = runTest {
    val viewModel = TodayForestViewModel(FakeMealRepository.cached(), FakeRecordMealUseCase())
    viewModel.load()
    assertTrue(viewModel.state.value.primaryActionEnabled)
    assertEquals("저장된 급식", viewModel.state.value.sourceLabel)
}
```

The Compose test must set font scale to 1.5, find `today_primary_action`, and assert `assertIsDisplayed()` and `assertHasClickAction()`.

- [ ] **Step 2: Run focused tests**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*TodayForestViewModelTest'`

Expected: FAIL because the child UI package does not exist.

- [ ] **Step 3: Implement the approved hierarchy and semantics**

Use Material 3 only as accessible primitives; apply project tokens instead of dynamic device colors. Mirror the iOS content order, the five difficulty reasons, and copy. Set `Modifier.heightIn(min = 48.dp)`, semantic headings, content descriptions, and stable test tags.

- [ ] **Step 4: Run unit, instrumentation, and debug build**

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt android/app/src/test android/app/src/androidTest
git commit -m "feat: build Android child meal loop"
```

### Task 8: 핵심 순환 동등성·오류 상태 검증

**Files:**
- Create: `docs/qa/native-rebuild-meal-loop-matrix.md`
- Create: `scripts/verify-meal-loop-contracts.sh`

**Interfaces:**
- Verifies: live, cached, empty, failed, allergy-risk, duplicate-record, daily-cap states

- [ ] **Step 1: Add the exact state matrix**

The matrix must list expected iOS and Android title, source label, primary action state, record result, XP, and motion for:

```text
live meal
cached meal while offline
no meal returned
NEIS 503 without cache
allergy-risk menu
duplicate oneBite record
daily total already at 100 XP
```

- [ ] **Step 2: Add an executable verification script**

```bash
#!/usr/bin/env bash
set -euo pipefail
python3 scripts/tests/test_native_rebuild_contracts.py
(cd android && ./gradlew testDebugUnitTest)
git diff --check
```

The script must print `meal-loop-contracts: PASS` only after every command succeeds.

- [ ] **Step 3: Run the complete child-loop gate**

Run: `bash scripts/verify-meal-loop-contracts.sh`

Expected: `meal-loop-contracts: PASS`.

Run: XcodeBuildMCP `test_sim`.

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/qa/native-rebuild-meal-loop-matrix.md scripts/verify-meal-loop-contracts.sh
git commit -m "test: verify child meal loop parity"
```
