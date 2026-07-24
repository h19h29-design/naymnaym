# Task 9 report — Settings, local deletion, and route recovery

Base SHA: `8c9c2956c0d869dafdd69fc0496da652e6e34cb4`
Implementation SHA: `5a73365915b2327c3c0e950bd8038b35d831cdb1`
Review hardening SHA: `13086d8f0e326ea9ecb01b46311cad10e17b5a4a`

## RED

- Added the settings page behavior tests before the page existed and ran
  `npm test -- src/features/settings/SettingsPage.test.tsx`. All six failed
  against the prior settings placeholder because the controls were absent.
- Added repository deletion-race tests before changing the repository and ran
  `npm test -- src/services/repository.test.ts`. Both new tests failed: a cache
  write and feedback journal write launched during deletion recreated keys.
- Added edit-mode onboarding coverage before its implementation and ran
  `npm test -- src/features/onboarding/OnboardingPage.test.tsx`. The new test
  failed because the existing profile did not prefill the form.
- Review follow-up RED: the new repository tests failed because overlapping
  deletion calls created independent promises, a failed removal left data
  partially deleted, and an old fetch had no epoch token to reject its cache
  write. The new `fetchMeal` signal test and deferred hook test also failed
  because the live request was not abortable on cleanup.

## GREEN

- Replaced the settings placeholder with a light TDS settings screen for
  profile/allergy editing, local data deletion, privacy, and support.
- Deletion is confirmed by the user, synchronously double-tap guarded, and
  disables pending controls. Successful deletion clears the provider’s live
  profile, progress, records, and challenges before replacing the route with
  onboarding; a failure preserves live state, shows the exact retry alert, and
  remains retryable.
- `deleteAll` now coalesces callers into a single pending promise, snapshots all
  five raw device values before removal, awaits every removal, and restores the
  exact snapshot before rejecting if any removal fails. All profile, progress,
  record, challenge, cache, and journal writes share the queue and deletion
  generation; no sixth storage key was introduced.
- Today’s live fetch captures the repository mutation epoch before requesting,
  receives an `AbortSignal`, and verifies the signal after the fetch before it
  can cache. A deferred fetch that ignores abort cannot recreate data after a
  successful deletion and route cleanup.
- The provider’s deterministic clear action invalidates earlier reload results,
  preserving its stable reload callback and preventing a stale completion from
  restoring deleted state.
- Policy/support actions use only the two approved HTTPS constants, are
  synchronously tap-guarded while opening, disable actions pending completion,
  and catch `openURL` rejection into an announced retryable safe error.
- Settings actions use installed TDS `List` and `ListRow` primitives with
  accessible TDS buttons; the destructive action keeps supported danger styling.
- Edit onboarding initializes once from a ready profile, retains `createdAt`,
  honors the existing `/today` and `/settings` next-path allowlist, and does not
  overwrite active edits on provider reload. It remains safe when no profile is
  present. No custom back bar was added; fallback routing remains configured
  user → today and new user → onboarding.

## Results

- Review-focused today/settings/onboarding/repository/NEIS/provider/routes
  suites: 98 tests passed across 7 files.
- Full client suite: 115 tests passed across 14 files.
- `npm run typecheck`: passed.
- `npm run build:web`: passed.
- `git diff --check`: passed.

## Note

- Vite retains the existing production chunk-size warning (1.31 MB minified /
  425.60 kB gzip); no new runtime dependency or native-app change was added.
