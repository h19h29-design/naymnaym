# Task 4 Report: Shared Nutrition and Idempotent Meal Recording

## Result

- Scope: Task 4 only in the `major-native-rebuild` worktree.
- Commit message: `feat: record meals with shared XP semantics`
- Review-fix commit message:
  `fix: harden meal XP identity and ledger accounting`
- Re-review-fix commit message:
  `fix: serialize migration and preserve signed XP verification`
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
- Daily caps classify an event by its canonical source date when present.
  Timestamp classification into the Asia/Seoul day interval is a fallback only
  for nil or noncanonical source IDs. This keeps migrated UUID and nil-source
  events classifiable without letting a backfilled timestamp override a
  canonical source date.
- iOS serializes the complete operation through the same global ledger
  serializer used by `RebuildProgressRepository` and
  `RebuildMigrationCoordinator`. Every writer first enters its managed-object
  context queue and only then enters the serializer, preventing lock inversion.
  Meal recording uses a new background context, computes a checked positive
  total before its single save, and rolls the context back on overflow or save
  failure.
- Android performs every identity check, cap query, record upsert, event insert,
  and total query inside Room `withTransaction`. An ignored insert reports zero
  rather than uncommitted XP. Runtime totals remain positive-only, while
  migration reconciliation uses a separate signed `Long` aggregate. The use
  case performs a checked conversion to its `Int` result and rolls the
  transaction back on overflow.
- Both nutrition engines reject an integral floating-point contract version
  such as `1.0`; the version must be encoded as a JSON integer.

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

### Re-review RED

- Android Room migration rejected a valid `+18/-8` legacy ledger because
  verification incorrectly used the runtime positive-only total and observed
  18 instead of the signed expected value 10.
- The bounded iOS default-shared-serializer regression timed out while a
  view-context writer held the serializer before it could enter the context
  queue.
- The new iOS migration concurrency test initially failed to compile because
  the coordinator did not accept an injectable ledger serializer.
- On both platforms, an event with canonical source date `2026-07-24` and a
  backfilled `occurredAt` on `2026-07-25` incorrectly consumed the latter day's
  cap.
- Swift accepted nutrition contract version `1.0`, unlike Kotlin.

The bounded iOS lock-order RED log is:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-48-52-932Z_pid22004_748d22c0.log
```

The iOS timestamp and nutrition RED log is:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-49-02-133Z_pid22004_a5a168dd.log
```

### Re-review GREEN

Shared contract tests and validator:

```text
python3 -m unittest scripts.tests.test_native_rebuild_contracts
python3 scripts/validate-native-rebuild-contracts.py
```

Result: 21 tests passed; validator reported `PASS`.

Focused iOS:

```text
test_sim extraArgs=[
  "-only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests",
  "-only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests",
  "-only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests"
]
```

Result: 79 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-51-37-843Z_pid22004_d8c3d187.log
```

Focused Android JVM:

```text
testDebugUnitTest \
  --tests '*RecordMealUseCaseTest' \
  --tests '*RebuildMigrationCoordinatorTest'
```

Result: 28 meal-recording and 12 migration tests passed, with no failures or
errors.

Android instrumentation:

```text
connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class='com.h19h29.naymnaymlevelup.rebuild.migration.RebuildMigrationIntegrationTest'
connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class='com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabaseTest'
```

Result: all 11 migration integration tests and all 3 Room database tests
passed on `naym_android_test(AVD)`. The migration suite includes signed
`+18/-8 = 10` reconciliation while confirming runtime `totalXp()` remains 18.

Full iOS:

```text
test_sim
```

Result: 227 passed, 0 failed, 0 skipped.

Log:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-25T08-52-46-766Z_pid22004_1700a254.log
```

Forced-clean Android:

```text
clean testDebugUnitTest compileDebugAndroidTestKotlin assembleDebug
```

Result: 96 unit tests passed, 0 failures, 0 errors; all 61 tasks executed;
Android instrumentation sources compiled; `app-debug.apk` was produced.

Re-review static checks:

```text
git diff --check
plutil -lint NaymNaymLevelUp.xcodeproj/project.pbxproj
```

Result: no whitespace errors; the project file reported `OK`.

## Residual Risk

- The Android concurrent duplicate behavior is exercised through the same
  transaction interface with a mutex-backed deterministic store, while the
  production Room adapter uses `withTransaction`. Its database contract,
  concurrent duplicate, and literal award-prefix tests also passed against
  Room on the Android emulator.
- Task 4 has no challenge-bonus input. It validates the configured challenge
  cap and counts existing challenge events toward the daily total; awarding new
  challenge bonuses remains future scope.
