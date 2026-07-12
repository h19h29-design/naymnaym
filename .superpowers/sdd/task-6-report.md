# Task 6 Report: Character Growth Screen

## Status

DONE

## Changed Files

- `NaymNaymLevelUp/Views/LevelUp/ProgressAndBadgesView.swift`
  - Adds `GrowthProgressPresentation` for level, next-stage, progress, and remaining-XP derivation from total stored XP.
  - Rebuilds the screen around the seven raster `GrowthCharacterView` stages with unlocked, current, and locked states.
  - Adds live evolution, outfit, badge, and story tabs backed by existing `PlayerProgress`, `CharacterSkin`, badge, and record data.
  - Keeps the complete current squirrel, next evolution preview, all four XP categories, and recent records accessible.
  - Uses cream, forest, orange, and teal surfaces with 8-point maximum card corners and no nested card hierarchy.
  - Adds explicit accessibility Dynamic Type stacking, one-column grids, and wider wrapping evolution cells.
- `NaymNaymLevelUpTests/ProgressLevelTests.swift`
  - Covers next-stage resolution, remaining XP, locked stage behavior, and the maximum-level terminal state.

## TDD Evidence

### RED

Focused `ProgressLevelTests` run on booted `NaymVerify iPhone 16` before production implementation:

```text
cannot find 'GrowthProgressPresentation' in scope
NaymNaymLevelUpTests/ProgressLevelTests.swift:62

cannot find 'GrowthProgressPresentation' in scope
NaymNaymLevelUpTests/ProgressLevelTests.swift:68

Test failed.
```

The failure was limited to the missing presentation type required by the new test.

### GREEN

Final focused XcodeBuildMCP run:

```text
21 tests passed, 0 failed, 0 skipped
```

The new test verifies:

- 30 total XP resolves to level 1, next level 2, and 50 XP remaining.
- Level 2 remains locked at 30 XP.
- 1,000 total XP resolves to level 7 with no next level and zero XP remaining.

## Verification

- Full simulator suite: `106 tests passed, 0 failed, 0 skipped`.
- App simulator build: passed.
- iPhone SE build/run: passed on `NaymVerify iPhone SE` (`440451DF-80A2-4871-8000-97245E601543`).
- Normal iPhone SE runtime: summary, horizontal seven-stage path, four segmented tabs, and complete current squirrel render without overlap or clipped labels.
- Each tab was activated and exposed live content: `성장 의상`, `뱃지 컬렉션`, and `최근 성장 스토리` were present in runtime UI snapshots.
- Accessibility XXXL runtime: summary switches to a vertical layout, progress captions stack, stage cells widen and wrap, grids become one column, and the complete squirrel remains uncropped. The simulator content size was restored to `large` afterward.
- `git diff --check`: passed before report creation; final staged checks are recorded in the commit workflow.

## Requirement Audit

- The current summary includes level, stage title, total XP, progress, and remaining XP.
- The evolution path contains exactly seven image-backed squirrel stages with clear completed/current/locked status.
- The default evolution view shows a large complete current squirrel and the next evolution or maximum-level reward state.
- Outfit unlocks use existing `CharacterSkin` level requirements without rendering the legacy avatar.
- Badge unlocks use the existing stored badge names and status.
- Recent records retain their existing XP breakdown and badge details under the story tab.
- Record, challenge, balance, and safety XP remain visible below the selected primary tab.
- The rebuilt source contains no `CharacterAvatar`, broccoli asset, emoji, placeholder, `RoundedCard`, or SwiftUI-drawn mascot reference.
- All explicit card corner radii are 8 points; circles are used only for familiar level/status/icon treatments.
- The implementation uses SwiftUI APIs available on the existing iOS 16 deployment target.
