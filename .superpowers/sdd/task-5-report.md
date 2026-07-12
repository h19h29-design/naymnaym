# Task 5 Report: Growth-Centered Today Dashboard and Connection Chip

## Status

DONE

## Changed Files

- `NaymNaymLevelUp/Views/Meals/GrowthHomeHeader.swift`
  - Adds the current image-backed growth character, nickname, level, stage, XP progress, record streak, total one-bite count, and actual-meal mission summary.
  - Derives streaks from stored challenge and meal record dates and returns zero when no activity exists.
  - Selects only safe, unrecorded items from the current `MealDay` for the mission.
- `NaymNaymLevelUp/Views/Parent/ParentConnectionStatusView.swift`
  - Adds the compact child/parent connection status chip for all `ParentConnectionState` cases.
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

- Focused `ProgressLevelTests` and `LocalStoreTests`: `63 tests passed, 0 failed, 0 skipped`.
- App target simulator build: passed.
- iPhone SE build/run: passed; the growth header, mission text, connection chip, and nutrition section render without clipping or overlap.
- `git diff --check`: passed.

## Requirement Notes

- The dashboard uses `GrowthCharacterView` at the current `PlayerProgress.level`; the old Today `CharacterAvatar` is removed.
- The palette uses cream, forest green, orange, and teal with one un-nested dashboard surface and compact 8-point corners.
- Actual connection is determined by `parentConnectedAt`; connected child screens keep only the compact chip and do not reopen invite instructions.
- Not-linked and invite-pending states continue to open the existing invite action.
- Parent mode suppresses generic invite guidance and successful sync banners after a child exists while retaining error visibility.
- Share, deep-link, server, allergy, meal-record, and record-sheet behavior is unchanged.
