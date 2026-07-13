# Meal Feedback and Parent Connection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Simplify meal feedback to three clear actions, add a safe motivational difficulty flow and whole-meal praise, and make completed parent connections prominent and role-aware on iOS and Android.

**Architecture:** Preserve the existing `EatingStatus`, XP, sharing, and Supabase contracts. Add small presentation/policy types for the three actions, make batch recording an `AppState` operation that skips allergy-risk items and prevents duplicate XP, then rebuild the iOS and Android surfaces around those contracts.

**Tech Stack:** SwiftUI, Swift 5, XCTest, Java, Android SDK 35, JUnit 4, Supabase parent-sync client, XcodeBuildMCP, Gradle.

## Global Constraints

- Keep iOS 16 and Android API 23 as minimum targets.
- Show only `한입도전`, `잘먹어요`, and `못먹겠어요` as menu-card actions.
- Keep `EatingStatus` and persisted JSON backward compatible.
- Keep one-bite actions locked for allergy-risk menus.
- Never mark allergy-risk menu items as finished through the whole-meal action.
- Keep daily base XP at 50, challenge bonus XP at 70, and total XP at 100.
- Hide invite-waiting copy and invite creation actions after a real connection is confirmed.
- Expose no server URL, Supabase, Edge Function, upload key, or internal model name in Settings.
- Child connection count is truthfully limited to `0` or `1` with the current server receipt.
- Parent connection count is the number of stored connected child links.
- Use existing raster/Lottie character assets; do not draw a mascot with SwiftUI shapes.

---

### Task 1: iOS Meal Feedback Policy and Safe Batch Recording

**Files:**
- Modify: `NaymNaymLevelUp/Models/AppModels.swift`
- Modify: `NaymNaymLevelUp/App/AppState.swift`
- Test: `NaymNaymLevelUpTests/ProgressLevelTests.swift`

**Interfaces:**
- Produces: `MealFeedbackAction` with `oneBite`, `enjoyed`, and `difficult` cases.
- Produces: `MealFeedbackAction.immediateStatus(isAllergyRisk:) -> EatingStatus?`.
- Produces: `MealBatchOutcome` with `recordedMenuNames`, `skippedAllergyMenuNames`, `gainedExp`, `newLevel`, and `didLevelUp`.
- Produces: `AppState.recordAllSafeMealsFinished(_ meal: MealDay, shareWithParent: Bool = false) -> MealBatchOutcome`.

- [x] **Step 1: Write failing action-mapping and batch-recording tests**

```swift
func testMealFeedbackActionsMapToExistingStatuses() {
    XCTAssertEqual(MealFeedbackAction.oneBite.immediateStatus(isAllergyRisk: false), .oneBite)
    XCTAssertEqual(MealFeedbackAction.enjoyed.immediateStatus(isAllergyRisk: false), .finished)
    XCTAssertNil(MealFeedbackAction.difficult.immediateStatus(isAllergyRisk: false))
    XCTAssertNil(MealFeedbackAction.oneBite.immediateStatus(isAllergyRisk: true))
}

@MainActor
func testRecordAllSafeMealsFinishedSkipsAllergyRiskAndDoesNotDuplicateXP() {
    let appState = makeAppState()
    appState.saveProfile(
        nickname: "냠냠이",
        school: School(name: "테스트초", officeCode: "B10", schoolCode: "123", region: "서울", address: "", schoolType: "초등학교"),
        allergyCodes: [1]
    )
    let meal = MealDay(
        date: "20260713",
        menuItems: [
            MealItem(name: "현미밥", allergyCodes: [], nutrients: ["탄수화물"], tags: [], sourceRawText: "현미밥"),
            MealItem(name: "우유", allergyCodes: [1], nutrients: ["칼슘"], tags: [], sourceRawText: "우유(1)")
        ],
        calorie: "500 Kcal",
        nutrition: .empty,
        isSample: false,
        notice: nil
    )

    let first = appState.recordAllSafeMealsFinished(meal)
    let second = appState.recordAllSafeMealsFinished(meal)

    XCTAssertEqual(first.recordedMenuNames, ["현미밥"])
    XCTAssertEqual(first.skippedAllergyMenuNames, ["우유"])
    XCTAssertEqual(appState.mealRecords.filter { $0.date == meal.date && $0.menuName == "현미밥" }.count, 1)
    XCTAssertEqual(second.gainedExp, 0)
    XCTAssertFalse(appState.mealRecords.contains { $0.date == meal.date && $0.menuName == "우유" && $0.eatingStatus == .finished })
}
```

- [x] **Step 2: Run the focused tests and verify RED**

Run with XcodeBuildMCP:
`test_sim({"extraArgs":["-only-testing:NaymNaymLevelUpTests/ProgressLevelTests"]})`

Expected: compile failure because `MealFeedbackAction`, `MealBatchOutcome`, and `recordAllSafeMealsFinished` do not exist.

- [x] **Step 3: Implement the three-action mapping and batch outcome**

```swift
enum MealFeedbackAction: String, CaseIterable, Identifiable {
    case oneBite
    case enjoyed
    case difficult

    var id: String { rawValue }

    func immediateStatus(isAllergyRisk: Bool) -> EatingStatus? {
        switch self {
        case .oneBite: return isAllergyRisk ? nil : .oneBite
        case .enjoyed: return .finished
        case .difficult: return nil
        }
    }
}

struct MealBatchOutcome: Identifiable, Equatable {
    let id = UUID()
    var recordedMenuNames: [String]
    var skippedAllergyMenuNames: [String]
    var gainedExp: Int
    var oldLevel: Int
    var newLevel: Int
    var didLevelUp: Bool { newLevel > oldLevel }
}
```

- [x] **Step 4: Implement idempotent safe batch recording**

Before recording each safe item, do nothing when a meal record with the same `date + normalized menu name` is already `.finished`. When replacing another meal status, upsert only the current `MealRecord`; keep prior `ChallengeRecord` entries as the immutable XP ledger so daily-cap accounting remains correct. Persist once at the end and publish one parent snapshot when sharing is enabled. Allergy-risk items are appended only to `skippedAllergyMenuNames`.

- [x] **Step 5: Run focused tests and verify GREEN**

Expected: all `ProgressLevelTests` pass and second batch execution grants `0 XP`.

- [x] **Step 6: Commit the policy change**

```bash
git add NaymNaymLevelUp/Models/AppModels.swift NaymNaymLevelUp/App/AppState.swift NaymNaymLevelUpTests/ProgressLevelTests.swift
git commit -m "feat: add simplified meal feedback policy"
```

---

### Task 2: iOS Three-Action Cards, Difficulty Guide, and Whole-Meal Praise

**Files:**
- Modify: `NaymNaymLevelUp/DesignSystem/DesignSystem.swift`
- Modify: `NaymNaymLevelUp/Views/Meals/TodayMealView.swift`
- Modify: `NaymNaymLevelUp/Views/Meals/MealDetailViews.swift`
- Test: `NaymNaymLevelUpTests/ProgressLevelTests.swift`

**Interfaces:**
- Consumes: `MealFeedbackAction` and `AppState.recordAllSafeMealsFinished`.
- Produces: `MealDifficultyGuideView(item:isChallengeLocked:onSave:)`.
- Produces: `WholeMealPraiseView(outcome:level:)`.
- Changes: `MealCard` callbacks to `onOneBite`, `onEnjoyed`, and `onDifficult` only.

- [x] **Step 1: Write failing presentation tests**

```swift
func testMealFeedbackActionTitlesAreTheThreeApprovedChoices() {
    XCTAssertEqual(MealFeedbackAction.allCases.map(\.title), ["한입도전", "잘먹어요", "못먹겠어요"])
}

func testWholeMealPraiseCopyMentionsExcludedWarningMenus() {
    let outcome = MealBatchOutcome(recordedMenuNames: ["현미밥"], skippedAllergyMenuNames: ["우유"], gainedExp: 10, oldLevel: 1, newLevel: 1)
    XCTAssertEqual(WholeMealPraisePresentation.title(for: outcome), "주의 메뉴를 제외한 오늘 급식을 잘 먹었어요!")
}
```

- [x] **Step 2: Run focused tests and verify RED**

Expected: compile failure because titles and `WholeMealPraisePresentation` do not exist.

- [x] **Step 3: Replace the four-button meal card with three stable actions**

Use a three-column `LazyVGrid` with stable minimum height and icons:

```swift
PrimaryButton("한입도전", systemImage: "star.fill", isDisabled: isAllergyRisk, action: onOneBite)
SecondaryButton("잘먹어요", systemImage: "hand.thumbsup.fill", action: onEnjoyed)
SecondaryButton("못먹겠어요", systemImage: "heart.text.square", action: onDifficult)
```

On iPhone SE, allow labels to wrap without shrinking below legible size. Remove `안내 보기` and `먹은 정도` from the card.

- [x] **Step 4: Build the motivational difficulty guide**

Reuse `NutritionEstimator.makeStudentExplanation(for:)` and `NutritionEstimator.makeGameStats(for:)`. Place the allergy safety card first when locked. Offer `.smelledOnly`, `.difficultToday`, and `.allergyAvoided`; show `그래도 한입도전` only for safe items. Reuse `DifficultyReason` toggles and return the selected status plus sorted reasons through `onSave`.

- [x] **Step 5: Add the whole-meal action and praise image**

Place `오늘 급식 다 잘먹었어요` above the list. Present `WholeMealPraiseView` with `GrowthCharacterView(level:size:pose: .celebrate)` and the batch result. Show recorded count, excluded warning count, and XP without exposing private details.

- [x] **Step 6: Run focused tests and verify GREEN**

Expected: action-title and praise-copy tests pass.

- [x] **Step 7: Commit the iOS meal UI**

```bash
git add NaymNaymLevelUp/DesignSystem/DesignSystem.swift NaymNaymLevelUp/Views/Meals/TodayMealView.swift NaymNaymLevelUp/Views/Meals/MealDetailViews.swift NaymNaymLevelUpTests/ProgressLevelTests.swift
git commit -m "feat: simplify iOS meal feedback flow"
```

---

### Task 3: iOS Connection Completion and Role-Aware Settings

**Files:**
- Modify: `NaymNaymLevelUp/Models/AppModels.swift`
- Modify: `NaymNaymLevelUp/App/AppState.swift`
- Modify: `NaymNaymLevelUp/Views/Parent/ParentConnectionStatusView.swift`
- Modify: `NaymNaymLevelUp/Views/Parent/ParentSummaryView.swift`
- Modify: `NaymNaymLevelUp/Views/Settings/SettingsView.swift`
- Test: `NaymNaymLevelUpTests/LocalStoreTests.swift`

**Interfaces:**
- Produces: `ConnectionOverview` with `role`, `connectedCount`, `title`, `message`, and `isConnected`.
- Produces: `AppState.connectionOverview`.
- Produces: `ParentConnectionPresentation.showsWaitingCopy(link:state:) -> Bool`.

- [x] **Step 1: Write failing connection presentation tests**

```swift
func testConnectedChildHidesWaitingCopyAndReportsOneParent() {
    var link = ChildLink(childNickname: "지우", schoolName: "냠냠초", mode: .elementary)
    link.parentConnectedAt = Date()

    XCTAssertFalse(ParentConnectionPresentation.showsWaitingCopy(link: link, state: .connected))
    XCTAssertEqual(ConnectionOverview.child(link: link).connectedCount, 1)
    XCTAssertEqual(ConnectionOverview.child(link: link).title, "보호자와 연결되었습니다")
}

func testParentOverviewReportsConnectedChildren() {
    let links = [
        ChildLink(childNickname: "지우", schoolName: "냠냠초", mode: .elementary),
        ChildLink(childNickname: "시준", schoolName: "냠냠중", mode: .middle)
    ]
    XCTAssertEqual(ConnectionOverview.parent(childLinks: links).connectedCount, 2)
    XCTAssertEqual(ConnectionOverview.parent(childLinks: links).title, "아이와 연결되었습니다")
}
```

- [x] **Step 2: Run `LocalStoreTests` and verify RED**

Expected: compile failure because `ConnectionOverview` and `showsWaitingCopy` do not exist.

- [x] **Step 3: Add truthful role-specific connection presentation**

For child modes, derive `0/1` from `childShareLink.parentConnectedAt`. For parent mode, derive `N` from `parentProfile.childLinks.count`. Do not infer a count from invite registration alone.

- [x] **Step 4: Make completed connection UI prominent and remove stale copy**

Use a full-width success card with `checkmark.circle.fill`, the connection title, and `연결된 보호자 1명` or `연결된 아이 N명`. Connected child screens must not render `childInviteHeader`, `childInviteSteps`, `inviteStatusBadge`, or `parentSyncMessage` from the invite flow. Parent screens only show request/code instructions when `childLinks.isEmpty`.

- [x] **Step 5: Replace the small registration badge with a success banner**

When `childShareLink.isCloudRegistered` is true but not connected, show `초대 링크 준비 완료` and the share/copy actions in a card-width green banner. After connection, replace the entire invitation card with the connected success card.

- [x] **Step 6: Add Settings connection counts and remove server internals**

Add a `연결 상태` section with a role-aware row. Remove the `서버 설정` diagnostic row and replace internal labels such as `childShareLink` with `아이 공유 준비`. Remove Supabase/Edge Function/upload-key wording from user-facing Settings and connection guides while keeping the build configuration unchanged.

- [x] **Step 7: Run `LocalStoreTests` and verify GREEN**

Expected: all connection tests pass.

- [x] **Step 8: Commit the iOS connection UI**

```bash
git add NaymNaymLevelUp/Models/AppModels.swift NaymNaymLevelUp/App/AppState.swift NaymNaymLevelUp/Views/Parent/ParentConnectionStatusView.swift NaymNaymLevelUp/Views/Parent/ParentSummaryView.swift NaymNaymLevelUp/Views/Settings/SettingsView.swift NaymNaymLevelUpTests/LocalStoreTests.swift
git commit -m "feat: clarify parent connection completion"
```

---

### Task 4: Android Meal and Connection Parity

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/MealFeedbackPolicy.java`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/MealFeedbackPolicyTest.java`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java`
- Modify: `android/app/build.gradle`

**Interfaces:**
- Produces: `MealFeedbackPolicy.safeBatch(List<MenuFeedbackItem>, Set<Integer>)`.
- Produces: `MealFeedbackPolicy.connectedCount(boolean childConnected, int parentChildren)`.
- Persists: parent-side connected child receipts as a JSON array in `SharedPreferences`.

- [x] **Step 1: Add JUnit and write failing Android policy tests**

```java
@Test public void safeBatchSkipsAllergyRiskMenus() {
    List<MenuFeedbackItem> items = Arrays.asList(
        new MenuFeedbackItem("현미밥", Collections.emptySet()),
        new MenuFeedbackItem("우유", Collections.singleton(1))
    );
    BatchSelection result = MealFeedbackPolicy.safeBatch(items, Collections.singleton(1));
    assertEquals(Collections.singletonList("현미밥"), result.recordedNames);
    assertEquals(Collections.singletonList("우유"), result.skippedNames);
}
```

Add `testImplementation "junit:junit:4.13.2"`.

- [x] **Step 2: Run Android unit tests and verify RED**

Run: `./gradlew :app:testDebugUnitTest`

Expected: compile failure because `MealFeedbackPolicy` does not exist.

- [x] **Step 3: Implement the Android policy and persistence**

Keep menu policy free of Activity dependencies. Store each successfully connected child using invite code, child nickname, and school name only; deduplicate by normalized invite code.

- [x] **Step 4: Replace Android menu actions and add the difficulty dialog**

Render `한입도전`, `잘먹어요`, and `못먹겠어요`. The difficulty dialog includes educational nutrient text, `냄새만 맡아봤어요`, `오늘은 어려워요`, and `알레르기·주의로 피했어요`. Allergy-risk items keep one-bite disabled.

- [x] **Step 5: Add whole-meal praise and connection completion cards**

The whole-meal action records only safe items and opens a dialog containing `R.drawable.mascot_jump`. Child mode shows `연결된 보호자 1명` after `parentConnectedAt`; parent connection results show `연결된 아이 N명` from persisted receipts. Hide waiting and invite instructions after connection.

- [x] **Step 6: Remove server implementation details from Android user copy**

Keep `BuildConfig.PARENT_SYNC_API_BASE_URL` internal. Remove user-visible `서버 등록`, server address, and backend technology wording; use `초대 링크 준비`, `연결 상태 확인`, and `연결 완료`.

- [x] **Step 7: Run Android tests and build**

Run:

```bash
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:bundleRelease
```

Expected: all tasks succeed.

- [x] **Step 8: Commit Android parity**

```bash
git add android/app/build.gradle android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java android/app/src/main/java/com/h19h29/naymnaymlevelup/MealFeedbackPolicy.java android/app/src/test/java/com/h19h29/naymnaymlevelup/MealFeedbackPolicyTest.java
git commit -m "feat: align Android meal and connection flow"
```

---

### Task 5: Cross-Platform Verification

**Files:**
- Update: `docs/superpowers/plans/2026-07-13-meal-feedback-parent-connection-implementation.md`
- Create verification artifacts under: `build/verification/meal-feedback-20260713/`

**Interfaces:**
- Produces: iPhone 16 and iPhone SE screenshots.
- Produces: Android debug APK and release AAB.
- Produces: clean test and diff evidence.

- [x] **Step 1: Run all iOS simulator tests**

Use XcodeBuildMCP `test_sim` with the project defaults. Expected: the complete `NaymNaymLevelUpTests` suite passes.

- [x] **Step 2: Build and launch iPhone 16 and iPhone SE**

Capture Today Meal, difficulty guide, whole-meal praise, connected child Settings, and connected parent Settings. Verify no overlap, no clipped action title, and no waiting copy after connection.

- [x] **Step 3: Run Android tests and release build**

Run: `cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:bundleRelease`

Expected: all tasks succeed and artifacts exist under `android/app/build/outputs/`.

- [x] **Step 4: Run repository checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only intended verification artifacts or plan checkbox updates remain.

- [x] **Step 5: Commit verification evidence**

```bash
git add docs/superpowers/plans/2026-07-13-meal-feedback-parent-connection-implementation.md
git commit -m "test: verify meal feedback and connection UX"
```
