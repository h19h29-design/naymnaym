# Task 3 Report: Android Cache-First Meal Repository

## Result

- Scope: Task 3 only in the `major-native-rebuild` worktree.
- Commit message: `feat: add cached Android meal repository`
- Added the Android meal domain, injected NEIS client/transport, cache-first
  repository, Room-backed store adapter, and focused JVM tests.
- Added the minimal `MealDayDao.delete(date)` query required for authoritative
  no-meal cache eviction.

## Behavior

- `observe(LocalDate)` is a collector-owned `Flow` with a replayed initial
  cached/empty state and ordered refresh transitions.
- Observer cancellation directly cancels its SharedFlow subscription; the
  repository does not retain per-observer jobs or continuations.
- Successful meals persist through `MealDayDao`; a new repository restores the
  JSON payload, fetch timestamp, and source.
- An authoritative no-meal response deletes the date row before publishing
  `Empty`.
- Network, parse, and persistence failures re-publish the existing cached meal;
  a failure without cache publishes `Failed`.
- Per-date generations enforce latest-request-wins for stale meal, no-meal, and
  error completions, protecting both state and persisted cache.
- State snapshots are read under the state mutex. Suspending store operations
  use per-date operation locks and never hold the global state mutex, so a
  blocked date does not block other dates.
- The constructor keeps the brief's `CoroutineScope` argument for API
  compatibility, but observation is deliberately collector-owned rather than
  launched in an external scope.
- `HttpURLConnection` is hidden behind `NeisTransport`; no networking or
  tracking SDK was added.
- The client parses `DDISH_NM`, allergy codes, `CAL_INFO`, and numeric
  `NTR_INFO`; it recognizes `INFO-200` as authoritative empty.
- String date entry uses strict `LocalDate` parsing before transport.
- Request logs replace the API key value with `KEY=<redacted>`.
- Core-library desugaring is enabled for `LocalDate`/`Instant` on minSdk 23.

## TDD Evidence

All Gradle commands used:

```text
JAVA_HOME=$HOME/.cache/codex-jdk17/extracted/Contents/Home
ANDROID_HOME=$HOME/Library/Android/sdk
ANDROID_SDK_ROOT=$ANDROID_HOME
./gradlew --init-script /tmp/task9-ascii-build.init.gradle \
  -Dorg.gradle.jvmargs='-Xmx3g -Dfile.encoding=UTF-8' \
  --max-workers=1 ...
```

### RED

Initial focused command:

```text
testDebugUnitTest --tests '*MealRepositoryTest'
```

Result: compilation failed as expected with unresolved `MealDay`,
`MealRepository`, `MealLoadState`, `MealDayStore`, and `MealClient`.

Subsequent focused RED cycles:

- Cache/flow lifecycle: failed for missing `observe` and injected clock.
- Latest request wins:
  `staleRefreshCompletionsCannotReplaceNewerStateOrCache` failed with an
  assertion after the older completion replaced the newer result.
- NEIS boundary: compilation failed for missing `NeisMealClient` and
  `NeisTransport`.
- Room adapter: compilation failed for missing `RoomMealDayStore` and the
  missing DAO delete contract.
- Cross-date synchronization:
  `suspendedCacheReadForOneDateDoesNotBlockAnotherDate` failed with
  `TimeoutCancellationException` while the old global mutex held a suspended
  cache read.

### GREEN

Focused Task 3 command:

```text
testDebugUnitTest --tests '*MealRepositoryTest'
```

Result: `12` tests, `0` failures, `0` errors; `BUILD SUCCESSFUL`.

Forced-clean full Android command:

```text
clean testDebugUnitTest assembleDebug
```

Result: `55` tests, `0` failures, `0` errors; `50` tasks executed;
`BUILD SUCCESSFUL in 41s`. The build ran `l8DexDesugarLibDebug` and
`desugarDebugFileDependencies`, and produced `app-debug.apk`.

Lint command:

```text
lintDebug
```

Result: `BUILD SUCCESSFUL in 19s`; `0` errors. The report contains `23`
pre-existing warnings and no issue referencing the Task 3 meal files,
`RebuildDao.kt`, coroutine-test, or desugaring.

Static checks:

```text
git diff --check
git status --short
```

Result: no whitespace errors; scope contains only the Task 3 report, Android
build configuration, the minimal meal DAO delete query, three meal production
files, and the focused test file.

## Review Fix

The follow-up review was implemented as a separate fix commit.

### Behavior hardened

- Cancellation after `Refreshing` now reconciles from the persistent store in
  `NonCancellable`, publishes the truthful cached, empty, or failed state for
  the current generation, and then rethrows the original cancellation.
- The cancellation path is deterministic both before and after a blocked store
  mutation completes. Store suspension remains outside the global state mutex.
- Present NEIS `mealServiceDietInfo` and `row` fields must have their documented
  array types. Wrong types are malformed responses rather than authoritative
  empty results, so a valid cache is preserved.
- A corrupt cached JSON row no longer aborts refresh. A successful network
  result replaces it; a network failure publishes `Failed` and leaves the row
  untouched.
- The default `HttpURLConnection` transport disconnects from its cancellation
  handler, while retaining configured timeouts and final cleanup.
- NEIS and Room decoding now share `MealJsonReader`; the duplicated Jackson
  token walkers were removed.

### Review TDD evidence

Focused RED cycles first demonstrated:

- all three cancellation cases remaining stuck in `Refreshing`;
- wrong-type NEIS containers being treated as empty and evicting cache;
- corrupt cached JSON preventing both replacement and truthful network failure;
- cancellation of a blocked default transport not disconnecting promptly.

After the fixes, the focused command:

```text
testDebugUnitTest --tests '*MealRepositoryTest'
```

passed `20` tests with `0` failures and `0` errors.

The final forced-clean command:

```text
clean testDebugUnitTest assembleDebug
```

passed `63` tests with `0` failures and `0` errors; all `50` tasks executed and
the build completed successfully in `9s`. Desugaring tasks ran and the debug APK
was produced.

The final `lintDebug` completed successfully in `9s` with `0` errors. Its `23`
warnings are pre-existing, and none reference the meal implementation or its
tests. `git diff --check` also passed.

## Final Strictness Review

The final re-review was also implemented as a separate fix commit.

- `MealJsonReader` now requires EOF after exactly one root object for both
  string and byte inputs. Trailing JSON tokens or non-JSON garbage are rejected
  by both NEIS and Room cache decoding.
- Every NEIS row is decoded into typed fields before date selection:
  `MLSV_YMD` and `DDISH_NM` are required strings, while present `CAL_INFO` and
  `NTR_INFO` values must be strings or null.
- A present `RESULT` must be an object with a required string `CODE`; present
  `MESSAGE` must be a string or null. Malformed rows and results can no longer
  be interpreted as authoritative empty responses.
- Repository regression coverage proves malformed row fields preserve an
  existing valid cache.

The focused RED run executed `25` tests and failed exactly the five new
strictness regressions: shared-reader EOF, NEIS trailing content, typed
row/result fields, repository cache preservation, and Room cache EOF. After the
implementation, the same focused suite passed `25/25` with no skipped tests,
failures, or errors.

The final forced-clean `clean testDebugUnitTest assembleDebug` run passed `68`
tests with `0` failures and `0` errors; all `50` tasks executed and the build
completed successfully in `9s`. The debug APK was produced. The final
`lintDebug` run also completed successfully in `9s` with `0` errors and the same
`23` pre-existing warnings; none reference the meal implementation or tests.
`git diff --check` passed.

## Residual Risk

- Cache identity remains date-only because that is the foundation schema and
  the cross-platform Task 2 contract. A later school-switch integration must
  clear or migrate date caches to prevent cross-school reuse.
- Lint's existing project warnings remain outside Task 3 scope.
