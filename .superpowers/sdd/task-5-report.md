# Task 5 Report: Growth-Centered Today Dashboard and Connection Chip

## Status

DONE

## Changed Files

- `NaymNaymLevelUp/Views/Meals/GrowthHomeHeader.swift`
  - Adds the current image-backed growth character, nickname, level, stage, XP progress, record streak, total one-bite count, and actual-meal mission summary.
  - Derives streaks from stored challenge and meal record dates and returns zero when no activity exists.
  - Selects only safe, unrecorded items from the current `MealDay` for the mission.
  - Uses `MealDataState`, loading state, and status messages to distinguish loading, confirmed no-meal, API/configuration failure, demo, and live nil-meal states.
  - Prioritizes unresolved allergy-risk items before safe-item missions or completion copy.
  - Switches profile, hero, mission, and metrics to vertical accessibility layouts when Dynamic Type enters an accessibility category.
- `NaymNaymLevelUp/Views/Parent/ParentConnectionStatusView.swift`
  - Adds the compact child/parent connection status chip for all `ParentConnectionState` cases.
  - Centralizes pure invite-action and connected-suppression rules and allows exact copy to wrap at accessibility sizes.
- `NaymNaymLevelUp/Views/Meals/TodayMealView.swift`
  - Replaces the legacy `CharacterAvatar` header with `GrowthHomeHeader`.
  - Refreshes child connection state on entry and pull-to-refresh.
  - Keeps the existing meal status, nutrition summary, `MealCard` loop, allergy locks, sheets, notices, and actions below the dashboard.
- `NaymNaymLevelUp/Views/Parent/ParentSummaryView.swift`
  - Shows connected child names prominently and hides generic invite guidance and stale success copy once children exist.
  - Keeps add-child available as a secondary action.
- `NaymNaymLevelUp/Models/AppModels.swift`
  - Adds pure child and parent message helpers to `ParentConnectionState`.
- `NaymNaymLevelUpTests/LocalStoreTests.swift`
  - Covers the exact required connection messages.
- `NaymNaymLevelUpTests/ProgressLevelTests.swift`
  - Covers honest streak calculation and safe actual-meal mission selection.
- `NaymNaymLevelUp.xcodeproj/project.pbxproj`
  - Registers both new source files in the app target.

## TDD Evidence

### RED: Connection Copy

The focused copy test failed as expected before implementation:

```text
value of type 'ParentConnectionState' has no member 'childMessage'
value of type 'ParentConnectionState' has no member 'parentMessage'
```

### GREEN: Connection Copy

```text
1 test passed, 0 failed, 0 skipped
```

### RED: Dashboard Presentation

The focused dashboard tests failed as expected before the new presentation type existed:

```text
cannot find 'GrowthHomePresentation' in scope
```

### GREEN: Dashboard Presentation

```text
2 tests passed, 0 failed, 0 skipped
```

## Verification

- Focused `ProgressLevelTests` and `LocalStoreTests`: `66 tests passed, 0 failed, 0 skipped`.
- Full simulator suite: `105 tests passed, 0 failed, 0 skipped`.
- App target simulator build: passed.
- iPhone SE build/run: passed; the growth header, mission text, connection chip, and nutrition section render without clipping or overlap.
- iPhone SE accessibility verification: passed at `accessibility-extra-extra-extra-large`; profile and hero stack vertically, nickname and mission copy wrap, metrics remain intact phrases, and the connection message remains fully readable after scrolling. The simulator was restored to `large` afterward.
- `git diff --check`: passed.

## Requirement Notes

- The dashboard uses `GrowthCharacterView` at the current `PlayerProgress.level`; the old Today `CharacterAvatar` is removed.
- The palette uses cream, forest green, orange, and teal with one un-nested dashboard surface and compact 8-point corners.
- Actual connection is determined by `parentConnectedAt`; connected child screens keep only the compact chip and do not reopen invite instructions.
- Not-linked and invite-pending states continue to open the existing invite action.
- Parent mode suppresses generic invite guidance and successful sync banners after a child exists while retaining error visibility.
- Share, deep-link, server, allergy, meal-record, and record-sheet behavior is unchanged.

## Review Follow-up TDD Evidence

### RED

The authoritative meal-state and visibility tests failed before implementation with the expected missing API errors:

```text
extra arguments at positions #2, #3, #4 in call
cannot infer contextual base in reference to member 'live'
```

The mixed-allergy and pure connection-visibility tests were part of the same red build; compilation stopped on the missing mission signature before emitting an independent visibility-helper diagnostic. The allergy regression covers a recorded safe item plus an unrecorded allergy-risk item at `1/2` and rejects completion copy.

A second red run proved loading could reuse stale status detail:

```text
XCTAssertEqual failed: ("이전 급식 오류 메시지") is not equal to ("학교 급식 정보를 확인하고 있어요.")
```

### GREEN

- Four new focused review regressions passed together.
- The stale-loading-message regression passed after loading copy became self-contained.
- The final focused and full suite results are recorded in Verification above.
