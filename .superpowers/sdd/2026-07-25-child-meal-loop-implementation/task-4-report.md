# Task 4 Report: Shared Nutrition and Idempotent Meal Recording

## Result

- Scope: Task 4 only in the `major-native-rebuild` worktree.
- Commit message: `feat: record meals with shared XP semantics`
- Review-fix commit message:
  `fix: harden meal XP identity and ledger accounting`
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
- XP is never deducted. Negative policy rewards are rejected, and each stored
  negative event contributes zero rather than cancelling positive daily or
  lifetime XP.
- Award identity is the policy-defined `date|normalizedMenuName`, while record
  and event identities retain status. A record or meal event in any status
  seals later status transitions at zero XP. Missing canonical counterparts are
  still repaired atomically with a zero-amount event.
- Daily caps include each event once when either its canonical source starts
  with the requested date or its timestamp falls within that date's
  Asia/Seoul day interval. This includes migrated UUID and nil-source events
  without requiring the command timestamp to match the command date.
- iOS serializes the complete operation through the same global ledger
  serializer used by `RebuildProgressRepository`, uses a new background
  context, computes a checked positive total before its single save, and rolls
  the context back on overflow or save failure.
- Android performs every identity check, cap query, record upsert, event insert,
  and total query inside Room `withTransaction`. An ignored insert reports zero
  rather than uncommitted XP. Room sums into `Long`; the use case performs a
  checked conversion to its `Int` result and rolls the transaction back on
  overflow.

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

### Final review-fix RED

- The new canonical policy test failed because `awardIdentityComponents`,
  `awardIdentity`, and `statusTransitionsGrantAdditionalXP` were absent.
- Focused iOS produced six failing regressions: status transitions earned more
  XP, migrated same-day events missed caps, negative corrections cancelled
  positive XP, overflow was discovered after save, and integral JSON floats
  were accepted.
- Focused Android first failed to compile on the missing typed `XpOverflow`
  result; the behavioral regressions then exercised the same transition, cap,
  positive-only, and rollback requirements.

The iOS review-fix RED log is:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-23-40-534Z_pid15208_f027f3e6.log
```

### Final review-fix GREEN

Shared contract tests and validator:

```text
python3 -m unittest scripts.tests.test_native_rebuild_contracts
python3 scripts/validate-native-rebuild-contracts.py
```

Result: 21 tests passed; validator reported `PASS`.

Focused iOS:

```text
test_sim extraArgs=["-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"]
```

Result: 26 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-30-02-846Z_pid15208_5b17e85e.log
```

Focused Android:

```text
testDebugUnitTest --tests '*RecordMealUseCaseTest'
```

Result: 26 passed, 0 failures, 0 errors.

Full iOS:

```text
test_sim
```

Result: 223 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-29-13-821Z_pid15208_7b42b64e.log
```

Forced-clean Android:

```text
clean testDebugUnitTest compileDebugAndroidTestKotlin assembleDebug
```

Result: 94 unit tests passed, 0 failures, 0 errors; all 61 tasks executed;
the Android instrumentation test sources compiled; `app-debug.apk` was
produced.

Room instrumentation:

```text
connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class='com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabaseTest'
```

Result: all 3 `RebuildDatabaseTest` tests passed on
`naym_android_test(AVD)`, including the `%`/`_` literal award-prefix
regression.

Final static checks:

```text
git diff --check
cmp contracts/native-rebuild/v1/xp-policy.json \
  NaymNaymLevelUp/Resources/RebuildContracts/xp-policy.json
cmp contracts/native-rebuild/v1/xp-policy.json \
  android/app/src/main/assets/rebuild-contracts/xp-policy.json
plutil -lint NaymNaymLevelUp.xcodeproj/project.pbxproj
```

Result: no whitespace errors, bundled contracts are byte-identical, and the
project file reported `OK`.

## Residual Risk

- The Android concurrent duplicate behavior is exercised through the same
  transaction interface with a mutex-backed deterministic store, while the
  production Room adapter uses `withTransaction`. Its database contract,
  concurrent duplicate, and literal award-prefix tests also passed against
  Room on the Android emulator.
- Task 4 has no challenge-bonus input. It validates the configured challenge
  cap and counts existing challenge events toward the daily total; awarding new
  challenge bonuses remains future scope.
