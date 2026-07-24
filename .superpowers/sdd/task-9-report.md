# Task 9 report — Settings, local deletion, and route recovery

Base SHA: `8c9c2956c0d869dafdd69fc0496da652e6e34cb4`
Implementation SHA: `5a73365915b2327c3c0e950bd8038b35d831cdb1`

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

## GREEN

- Replaced the settings placeholder with a light TDS settings screen for
  profile/allergy editing, local data deletion, privacy, and support.
- Deletion is confirmed by the user, synchronously double-tap guarded, and
  disables pending controls. Successful deletion clears the provider’s live
  profile, progress, records, and challenges before replacing the route with
  onboarding; a failure preserves live state, shows the exact retry alert, and
  remains retryable.
- Repository writes carry a deletion generation. Mutations or feedback journal
  writes that begin while deletion is active are skipped, so the five-device-key
  deletion cannot be followed by a late cache or journal recreation.
- The provider’s deterministic clear action invalidates earlier reload results,
  preserving its stable reload callback and preventing a stale completion from
  restoring deleted state.
- Policy/support actions use only the two approved HTTPS constants and catch
  `openURL` rejection into an announced safe error.
- Edit onboarding initializes once from a ready profile, retains `createdAt`,
  honors the existing `/today` and `/settings` next-path allowlist, and does not
  overwrite active edits on provider reload. It remains safe when no profile is
  present. No custom back bar was added; fallback routing remains configured
  user → today and new user → onboarding.

## Results

- Focused settings/onboarding/repository/provider/routes suites: 64 tests
  passed across 5 files.
- Full client suite: 105 tests passed across 14 files.
- `npm run typecheck`: passed.
- `npm run build:web`: passed.
- `git diff --check`: passed.

## Note

- Vite retains the existing production chunk-size warning (1.31 MB minified /
  425.26 kB gzip); no new runtime dependency or native-app change was added.
