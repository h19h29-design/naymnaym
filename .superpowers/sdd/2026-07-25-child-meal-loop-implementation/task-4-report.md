# Task 4 Report: Shared Nutrition and Idempotent Meal Recording

## Result

- Scope: Task 4 only in the `major-native-rebuild` worktree.
- Commit message: `feat: record meals with shared XP semantics`
- Added equivalent Swift and Kotlin nutrition rule engines and record-meal use
  cases.
- Both runtimes load the synced bundled `nutrition-rules.json` and
  `xp-policy.json`; no XP or keyword table is duplicated in source.

## Behavior

- The exact shared spinach fixture returns nutrient IDs `fiber, vitamin`, grants
  18 XP on the first canonical event, and grants 0 XP on replay.
- Nutrition matches case-insensitive substrings, de-duplicates matches, then
  emits them in `nutrientOrder` regardless of rule-array order. Child names,
  alternatives, omission copy, and the educational notice come from the bundled
  contract.
- Malformed, missing, negative-XP, unsafe-copy, and legacy-status-promoting
  contracts fail deterministically before persistence.
- Record identity is exactly
  `yyyy-MM-dd|trim-and-lowercase(menuName)|activeStatus`; invalid dates, blank or
  separator-injected names, mismatched IDs, and legacy `half` commands are
  rejected.
- Allergy-coded meals must use `allergyAvoided`. Difficult records return
  `comfort`; accepted progress and safety records return `mealSuccess`.
- Status XP is the Task 4 base component. It is capped by the policy base cap
  and daily total cap. Existing challenge events count toward the total cap,
  while the challenge cap is validated for the future challenge-bonus path.
- XP is never deducted. Negative policy rewards are rejected.
- A pre-existing canonical record or progress event seals XP at zero. If one
  counterpart is missing, the transaction repairs it without awarding XP.
- iOS serializes the complete operation, uses a new background context, saves
  the meal record and progress event once, and rolls the context back on any
  error.
- Android performs every identity check, cap query, record upsert, event insert,
  and total query inside Room `withTransaction`. An ignored insert reports zero
  rather than uncommitted XP.

## TDD Evidence

XcodeBuildMCP profile: `major-native-rebuild`

### Initial RED

iOS:

```text
test_sim extraArgs=["-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"]
```

Failed during compilation because `NutritionRuleEngine`,
`RecordMealUseCase`, `RecordMealCommand`, and `RecordMealResult` did not exist.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-01-49-256Z_pid8138_36d04fdd.log
```

Android:

```text
testDebugUnitTest --tests '*RecordMealUseCaseTest'
```

Failed during compilation with the equivalent unresolved Kotlin engine, command,
result, status, motion, and use-case types.

### Review REDs

- Reordered valid nutrition rules produced rules-array order and unsafe child
  copy was accepted on both platforms.
- Android reported 18 XP when the event insert returned an ignored conflict.
- A structurally valid tampered policy could promote legacy `half` into the
  active set on both platforms.

The iOS nutrition review RED log is:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-07-19-641Z_pid8138_61727e8f.log
```

The iOS legacy-policy RED log is:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-10-57-724Z_pid8138_916af631.log
```

### GREEN

Shared contract tests:

```text
python3 scripts/tests/test_native_rebuild_contracts.py
```

Result: 20 passed.

Focused iOS:

```text
test_sim extraArgs=["-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"]
```

Result: 17 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-11-28-959Z_pid8138_1dccfc34.log
```

Focused Android:

```text
testDebugUnitTest --tests '*RecordMealUseCaseTest'
```

Result: 18 passed, 0 failed, 0 errors.

Full iOS:

```text
test_sim
```

Result: 214 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-12-18-437Z_pid8138_420a0935.log
```

Forced-clean Android:

```text
clean testDebugUnitTest assembleDebug
```

Result: 86 tests passed, 0 failures, 0 errors; all 50 tasks executed;
`app-debug.apk` was produced. The build used JDK 17, the requested ASCII init
script, `-Xmx3g`, and `--max-workers=1`.

Static checks:

```text
git diff --check
plutil -lint NaymNaymLevelUp.xcodeproj/project.pbxproj
```

Result: no whitespace errors; project file reported `OK`.

## Residual Risk

- The Android concurrent duplicate behavior is exercised through the same
  transaction interface with a mutex-backed deterministic store, while the
  production Room adapter is compile-checked and uses `withTransaction`.
  No connected-device Room concurrency test was required by Task 4.
- Task 4 has no challenge-bonus input. It validates the configured challenge
  cap and counts existing challenge events toward the daily total; awarding new
  challenge bonuses remains future scope.
