# Squirrel Growth Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype mascot UI with the approved squirrel growth experience while preserving meal, allergy, XP, badge, and parent-sharing behavior and showing truthful parent connection states.

**Architecture:** Add a privacy-minimal server connection receipt (`connected_at`) and expose it through the existing parent-sync service. Introduce one level-to-asset resolver shared by intro, home, and progress screens, then refactor the existing views around reusable dashboard components without replacing their data flows.

**Tech Stack:** SwiftUI, Swift 5, XCTest, Supabase Edge Functions (TypeScript/Deno), PostgreSQL migration, Figma, XcodeBuildMCP.

## Global Constraints

- Keep iOS 16 as the minimum deployment target.
- Keep real NEIS failures and no-meal days free of sample fallback.
- Keep one-bite actions locked for allergy-risk menus.
- Store no parent name or parent account identity in the child connection record.
- Keep existing invite codes valid.
- Use raster squirrel assets; do not draw the mascot with SwiftUI shapes.
- Verify iPhone 16 and iPhone SE layouts.

---

### Task 1: Truthful Parent Connection Contract

**Files:**
- Create: `supabase/migrations/20260712_parent_connection_receipt.sql`
- Modify: `supabase/functions/parent-sync/index.ts`
- Modify: `NaymNaymLevelUp/Models/AppModels.swift`
- Modify: `NaymNaymLevelUp/Stores/LocalStores.swift`
- Modify: `NaymNaymLevelUp/App/AppState.swift`
- Test: `NaymNaymLevelUpTests/LocalStoreTests.swift`

**Interfaces:**
- Produces: `ChildLink.parentConnectedAt: Date?`
- Produces: `ParentConnectionState` with `notLinked`, `invitePending`, `connected`, and `syncError` cases.
- Produces: `ServerParentLinkService.fetchConnectionStatus(childLink:) async throws -> Date?`
- Produces: `AppState.refreshChildConnectionStatus() async`

- [ ] **Step 1: Write failing model and service tests**

```swift
func testChildConnectionStateDistinguishesInviteFromActualConnection() {
    let pending = ChildLink(childNickname: "지우", schoolName: "냠냠초", mode: .elementary, registeredAt: Date())
    var connected = pending
    connected.parentConnectedAt = Date()

    XCTAssertEqual(ParentConnectionState.resolve(link: nil, syncError: nil), .notLinked)
    XCTAssertEqual(ParentConnectionState.resolve(link: pending, syncError: nil), .invitePending)
    XCTAssertEqual(ParentConnectionState.resolve(link: connected, syncError: nil), .connected)
    XCTAssertEqual(ParentConnectionState.resolve(link: connected, syncError: "network"), .syncError)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:
`xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -destination 'platform=iOS Simulator,name=NaymVerify iPhone 16' -only-testing:NaymNaymLevelUpTests/LocalStoreTests`

Expected: compile failure because `parentConnectedAt` and `ParentConnectionState` do not exist.

- [ ] **Step 3: Add the nullable database receipt and Edge Function actions**

```sql
alter table public.nyam_parent_links
    add column if not exists connected_at timestamptz;
```

`connectInvite` updates `connected_at` with the first successful parent connection. A new `checkConnectionStatus` action validates `childLinkId + inviteSecret` and returns only `connectedAt`.

- [ ] **Step 4: Add backward-compatible Swift model and service support**

`ChildLink.parentConnectedAt` must default to `nil` during decoding. `fetchConnectionStatus` must use the existing secret-safe request path and never send or log the secret.

- [ ] **Step 5: Run focused tests and verify GREEN**

Expected: all `LocalStoreTests` pass.

---

### Task 2: Growth Character Asset Resolver

**Files:**
- Create: `NaymNaymLevelUp/Models/GrowthCharacterAssets.swift`
- Create: `NaymNaymLevelUp/DesignSystem/Components/GrowthCharacterView.swift`
- Modify: `NaymNaymLevelUp/Models/AppModels.swift`
- Add: `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Atlas.imageset`
- Test: `NaymNaymLevelUpTests/ProgressLevelTests.swift`

**Interfaces:**
- Produces: `GrowthCharacterAssets.atlasCell(for level: Int) -> Int`
- Produces: `GrowthCharacterAssets.stageTitle(for level: Int) -> String`
- Produces: `GrowthCharacterView(level:size:pose:)`

- [ ] **Step 1: Write failing level mapping tests**

```swift
func testGrowthCharacterAssetsClampLevelsAndResolveEveryStage() {
    XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: 0), 0)
    XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: 4), 3)
    XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: 99), 6)
}
```

- [ ] **Step 2: Run focused test and verify RED**

Expected: compile failure because `GrowthCharacterAssets` does not exist.

- [ ] **Step 3: Produce the seven consistent squirrel raster assets**

Use the approved reference for face, fur, sprout, proportions, palette, and rendering. Generate one purpose-built 4×2 growth atlas with seven equal cells and one empty cell. The atlas must have a transparent background and enough resolution for each cell to support a 300pt hero rendering. This is a dedicated app asset, not a crop of the supplied screenshot.

- [ ] **Step 4: Implement the resolver and image-backed SwiftUI view**

The view uses `Image("Squirrel_Growth_Atlas")`, scales the 4×2 atlas to the requested cell, clips exactly one cell using `GrowthCharacterAssets.atlasCell(for:)`, keeps a stable aspect ratio, and provides accessibility text. It must not contain a SwiftUI-drawn mascot.

- [ ] **Step 5: Run focused tests and verify GREEN**

Expected: all `ProgressLevelTests` pass and the atlas asset resolves in the built bundle.

---

### Task 3: Figma Implementation Reference

**Files:**
- Update existing Figma file `PzhrBaw0BuAMNTX4BPyfsM`

**Interfaces:**
- Produces: page `Squirrel Growth Redesign 2026-07-12`
- Produces: frames `Intro / iPhone 16`, `Home / iPhone 16`, `Character / iPhone 16`, `Core / iPhone SE`, and `Connection States`

- [ ] **Step 1: Create reusable color, text, card, progress, and connection-state components**

Use cream `#FFF9EE`, forest `#527A2D`, orange `#E58A2E`, teal `#1FA6A7`, dark text `#3B3024`, and semantic red only for errors/allergy warnings.

- [ ] **Step 2: Build the three reference screens and SE layout**

Match the approved image hierarchy while keeping native iOS navigation and tab patterns.

- [ ] **Step 3: Capture Figma screenshots and verify hierarchy**

Confirm character scale, first-viewport priorities, text wrapping, card spacing, and connection states.

---

### Task 4: Intro Uses the Current Growth Character

**Files:**
- Modify: `NaymNaymLevelUp/Views/Onboarding/IntroExperienceView.swift`
- Modify: `NaymNaymLevelUp/App/RootView.swift`
- Test: `NaymNaymLevelUpTests/MealParserTests.swift`

**Interfaces:**
- Consumes: `GrowthCharacterView(level:size:pose:)`
- Preserves: `IntroMissionTextFactory.make(...) -> IntroMission`

- [ ] **Step 1: Add a failing intro character-level test**

```swift
func testIntroCharacterPresentationUsesCurrentProgressLevel() {
    XCTAssertEqual(IntroCharacterPresentation.atlasCell(level: 5), 4)
    XCTAssertEqual(IntroCharacterPresentation.atlasCell(level: nil), 0)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

- [ ] **Step 3: Replace mascot rendering with the current-level squirrel hero**

Keep the existing mission state machine, loading/error/demo copy, and buttons. Apply rise, bounce, wave, and sparkle animations to the image-backed character.

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: intro state tests pass without changing live/demo/no-meal behavior.

---

### Task 5: Growth-Centered Today Dashboard and Connection Chip

**Files:**
- Create: `NaymNaymLevelUp/Views/Meals/GrowthHomeHeader.swift`
- Create: `NaymNaymLevelUp/Views/Parent/ParentConnectionStatusView.swift`
- Modify: `NaymNaymLevelUp/Views/Meals/TodayMealView.swift`
- Modify: `NaymNaymLevelUp/Views/Parent/ParentSummaryView.swift`
- Test: `NaymNaymLevelUpTests/ProgressLevelTests.swift`
- Test: `NaymNaymLevelUpTests/LocalStoreTests.swift`

**Interfaces:**
- Consumes: `ParentConnectionState`
- Produces: `GrowthHomeHeader` with character, level, progress, streak, challenge count, and mission.
- Produces: `ParentConnectionStatusView(state:connectedName:onTap:)`

- [ ] **Step 1: Write failing presentation-copy tests**

```swift
XCTAssertEqual(ParentConnectionState.notLinked.childMessage, "아직 보호자와 연결되지 않았어요")
XCTAssertEqual(ParentConnectionState.connected.childMessage, "보호자와 연결되었습니다")
XCTAssertEqual(ParentConnectionState.connected.parentMessage(childName: "지우"), "지우와 연결되었습니다")
```

- [ ] **Step 2: Run focused tests and verify RED**

- [ ] **Step 3: Add the dashboard while preserving the existing meal list**

Move the existing nutrition summary and `MealCard` loop below the new dashboard. Do not change record, allergy, or share actions.

- [ ] **Step 4: Hide repetitive invite UI after actual connection**

Show only the compact connected chip once `parentConnectedAt != nil`. Keep the invite action visible for `notLinked` and `invitePending` states. Clear success banners after state refresh.

- [ ] **Step 5: Run focused tests and verify GREEN**

---

### Task 6: Character Growth Screen

**Files:**
- Modify: `NaymNaymLevelUp/Views/LevelUp/ProgressAndBadgesView.swift`
- Test: `NaymNaymLevelUpTests/ProgressLevelTests.swift`

**Interfaces:**
- Consumes: `GrowthCharacterAssets`, `PlayerProgress`, and existing badge records.

- [ ] **Step 1: Add failing progress presentation tests**

```swift
func testGrowthProgressPresentationResolvesNextStageAndRemainingXP() {
    let levelOne = GrowthProgressPresentation(progress: PlayerProgress(recordExp: 30))
    XCTAssertEqual(levelOne.currentLevel, 1)
    XCTAssertEqual(levelOne.nextLevel, 2)
    XCTAssertEqual(levelOne.remainingXP, 50)
    XCTAssertFalse(levelOne.isStageUnlocked(2))

    let maxLevel = GrowthProgressPresentation(progress: PlayerProgress(recordExp: 1_000))
    XCTAssertEqual(maxLevel.currentLevel, 7)
    XCTAssertNil(maxLevel.nextLevel)
    XCTAssertEqual(maxLevel.remainingXP, 0)
}
```

- [ ] **Step 2: Run focused test and verify RED**

- [ ] **Step 3: Rebuild the screen hierarchy**

Implement current level summary, evolution path, tabs, large current character, next reward preview, and badge collection. Keep detailed four-category XP accessible below the primary progress section.

- [ ] **Step 4: Run focused tests and verify GREEN**

---

### Task 7: End-to-End Verification and Commit

**Files:**
- Create: `build/verification/squirrel-intro-iphone16-20260712.jpg`
- Create: `build/verification/squirrel-home-iphone16-20260712.jpg`
- Create: `build/verification/squirrel-character-iphone16-20260712.jpg`
- Create: `build/verification/squirrel-core-iphonese-20260712.jpg`
- Create: `build/verification/squirrel-connection-states-20260712.jpg`
- Create: `design-qa.md`

- [ ] **Step 1: Run the entire simulator test suite**

Run: XcodeBuildMCP `test_sim`
Expected: all tests pass with zero failures.

- [ ] **Step 2: Build and run on iPhone 16 and iPhone SE**

Verify no clipped text, horizontal scrolling, overlapping tab bars, or inaccessible primary actions.

- [ ] **Step 3: Capture and compare all required states**

Compare the same screen state against the approved reference and Figma frames. Fix P0/P1/P2 differences and record the result in `design-qa.md` with `final result: passed`.

- [ ] **Step 4: Verify repository state**

Run: `git diff --check`
Expected: exit 0.

- [ ] **Step 5: Commit the implementation**

```bash
git add NaymNaymLevelUp NaymNaymLevelUpTests supabase design-qa.md docs/superpowers/plans/2026-07-12-squirrel-growth-dashboard-implementation.md
git commit -m "Redesign app around squirrel growth journey"
```
