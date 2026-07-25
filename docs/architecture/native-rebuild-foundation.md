# Native rebuild foundation

## Activation boundary

The native rebuild is disabled by default and is for local debug verification
only. It is not enabled for a release or any deployment.

- **iOS:** `RootView` uses the rebuild only when `RebuildFeatureGate` returns
  true. For a simulator-only check, add this launch argument in the scheme:

  ```text
  -native-rebuild-enabled YES
  ```

  The gate accepts `YES` (case-insensitive) after that argument; otherwise it
  reads the `native-rebuild-enabled` UserDefaults key, whose absent/default
  Boolean value is false. Remove the launch argument after checking the local
  rebuild.

- **Android:** committed `defaultConfig` keeps
  `BuildConfig.NATIVE_REBUILD_ENABLED` as `false`; `MainActivity` opens the
  non-exported `RebuildActivity` only when that value is true. For a local
  debug-only check, make an uncommitted edit that adds this override inside the
  existing `buildTypes.debug` block in `android/app/build.gradle`:

  ```groovy
  buildConfigField "boolean", "NATIVE_REBUILD_ENABLED", "true"
  ```

  Build and verify `RebuildActivity`, then remove the override. Do not change
  the committed `defaultConfig` value and do not add the override to `release`.

No flag change, release build, rollout, or deployment is authorized by this
foundation documentation.

## Rebuild stores and schema v1

| Platform | Rebuild store | Schema / migration target |
| --- | --- | --- |
| iOS | `NaymRebuild.sqlite`, a Core Data SQLite store named `NaymRebuild` | Rebuild schema v1: the migration coordinator supports target version `1` and records `rebuild-migration`. |
| Android | `naym-rebuild.db`, opened by Room `RebuildDatabase` | Room schema version `1`; the migration coordinator supports target version `1` and records `rebuild-migration`. |

## Legacy migration sources

Migration is additive into the rebuild stores. Source records remain untouched:
the iOS reader only reads legacy stores, and the Android reader has no
`SharedPreferences.Editor` and never clears, removes, or rewrites a legacy
preference. A migration failure rolls back target writes before its completion
record is written; it does not alter the source.

### iOS UserDefaults source keys

`LegacyDefaultsReader` reads these exact persistent-domain keys:

| Key | Target preservation / mapping |
| --- | --- |
| `user-profile` | A `RebuildProfile` preserves the profile UUID string, derived role, nickname, school codes, and allergy codes. |
| `player-progress` | Its stored progress is used to verify total XP; any difference from challenge XP becomes a deterministic reconciliation event. |
| `meal-records` | Each record becomes a `RebuildMealRecord` with date, menu/status identity, reasons, allergies, photo IDs, parent-share state, and timestamps carried to the target. |
| `meal-photo-records` | Each metadata record becomes a `RebuildMealPhoto`; its ID and time are preserved. A present, verified source photo is copied into the rebuild cache without deleting the source photo; a missing source photo produces a warning and deterministic target metadata. |
| `challenge-records` | Each challenge becomes a `RebuildProgressEvent` retaining its source challenge ID, XP amount, and time. |
| `parent-profile` | It supplies a parent `RebuildProfile` only when `user-profile` is absent and supplies parent links; target links are deduplicated by ID/normalized invite code. |
| `child-share-link` | It becomes a `RebuildParentLink` retaining exactly `id`, `inviteCode`, `connectionState`, and `connectedAt`. `inviteSecret` and registration metadata remain only in the untouched legacy source; iOS rebuild v1 does not store them. |

### Android SharedPreferences source keys

`LegacyPreferencesReader` is a read-only projection of the exact
`naymnaym-android` preferences file. It reads these keys:

| Source keys | Target preservation / mapping |
| --- | --- |
| `schoolName`, `officeCode`, `schoolCode`, `region`, `address`, `schoolType` | All six keys are read and included in the logical source and digest. v1 `ProfileEntity` persists only `officeCode` and `schoolCode`; `schoolName`, `region`, `address`, and `schoolType` remain only in the untouched legacy source. The legacy profile ID and nickname are deterministic because this schema did not store them. |
| Every `dailyBaseXp-*` key | The non-negative `Int` entries provide stored total XP and are retained in the migration source digest. |
| `mealSnapshotLedger` | Its `latestMeals` array becomes meal records and its `actions` array becomes challenge-derived progress events. |
| `parentChildren` | Its JSON array becomes parent links. |
| `childLinkId`, `inviteCode`, `inviteSecret`, `registeredAt`, `parentConnectedAt` | Present scalar child-link fields become one parent link. |

The shipped Android source has no meal-photo preference or file-metadata key,
so its logical meal-photo payload is absent rather than synthesized. Both
platforms hash the present source data for the completion record and verify
target rows before recording version 1 completion.

## Android test-path caveat

In this Korean/Unicode workspace path, Kotlin 2.2.21 may fail to compile
same-module Kotlin test sources for `testDebugUnitTest` or Android
instrumentation tests unless an uncommitted Gradle init script redirects only
build outputs to an ASCII `/tmp` directory. That workaround must not be
committed; it does not change the real source tree, committed build files, or
release configuration.
