# Task 8 report — Today meal, feedback, demo, and growth

Base SHA: `dacc65b6f4053acb742f85a7f61517f9f2e63f5a`
Implementation SHA: `f7ea3eae14412113ab38bac05b3250ba048b032a`
Review follow-up SHA: `19e162677d8bb428a2e12f6b6bf8cfa86e66732b`
Journal hardening SHA: `3b6393c3b74f146176dc6c053f36b42ab5f80aac`

## RED

- Added the first `TodayPage` behavior tests before the page existed.
- Ran `npm test -- src/features/today/TodayPage.test.tsx` and observed the
  expected missing `TodayPage` module failure.

## GREEN

- Implemented explicit live, exact-date cache, no-meal, error, and explicit-demo
  branches without any live-to-demo fallback.
- Added Seoul-date loading, safe cache failure handling, stale effect suppression,
  allergy-safe actions, detailed feedback modal, guarded record persistence and
  retry, demo-only local state, and XP/growth feedback.
- Copied exactly seven non-empty native PNG growth assets (`level-1` through
  `level-7`) and added no new runtime dependencies.
- Review follow-up: a ready-state reload now preserves the mounted route on
  failure; feedback writes use a validated journal inside `progress:v1` and
  recover with a fresh repository instance; fetched and cached meal payloads
  are validated before use; the today hook schedules Seoul-midnight refreshes
  and refreshes on focus/visibility changes.
- Re-review follow-up: repository operations are serialized per instance;
  `saveProgress` refuses to overwrite a validated pending feedback journal;
  journal snapshots require complete non-negative integer progress with canonical
  meal-date XP maps, while legacy top-level partial progress remains readable.

## Results

- Focused repository/provider/today/routes suites: 53 tests passed.
- Full client suite: 94 tests passed across 13 files.
- `npm run typecheck`: passed.
- `npm run build:web`: passed.
- Asset audit: 7 PNG files, all non-empty; no other public assets.
- `git diff --check`: passed.

## Risks

- The seven public PNG files add 8,735,557 bytes. The production build still
  emits Vite's single-chunk warning: 1.31 MB minified / 424.61 kB gzip.
- Device storage lacks a native transaction. The verified `progress:v1` journal
  carries an immutable feedback snapshot before companion writes and is replayed
  on the next repository load; crash injection after every journal/record/
  challenge/final-progress write converges idempotently without a sixth key.
- A normal progress write cannot erase a valid journal: it is serialized and
  rejected until recovery completes; incomplete journal progress invalidates only
  `progress:v1`, preserving unrelated device keys.
