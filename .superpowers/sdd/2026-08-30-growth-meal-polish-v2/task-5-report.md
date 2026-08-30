# Task 5 report — immutable nutrition sidecar

## Commit

- Base: `5cb270e9923562937a305159840ddc4ec3caad7c` (reviewed Task 4 head)
- Commit: `8a1af43`
- Message: `feat: store nutrition guidance by meal revision`

## Scope and files

Implemented only the Task 5 immutable, exact-revision nutrition sidecar surface:

- `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`
- `NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift`
- `NaymNaymLevelUp/Rebuild/Meal/NutrientImpactSidecar.swift`
- `NaymNaymLevelUpTests/NutrientImpactSidecarTests.swift`

No Core Data model or migration file changed. No progress ledger, release metadata, assets, Android behavior, dependencies, network/upload, UI, meal transaction, growth/XP, legacy defaults, or existing meal-record data changed.

## TDD and verification

- RED first: focused sidecar + public schema suite reached 20/23 test cases (four assertion failures across three sidecar cases); failures covered the initial validation/read-back behavior.
- RED second: focused sidecar + public schema suite reached 22/23 test cases (one sidecar validation assertion remained).
- GREEN: focused sidecar + public schema suite — 23/23 test cases passed, twice (`task5-focused-green3.log`, `task5-focused-green4.log`).
- GREEN: full iOS suite — 427/427 tests passed (`task5-full-ios.log`).
- `git diff --check` — PASS.
- Project membership check — each new Swift path exists once; each has one file reference, one target-group entry, and one Sources build entry in the project file.
- Core Data/migration scope check — no matching model/migration path in the diff.

## Architecture and safety notes

- `NutrientImpactSnapshot` is schema-version 1 and binds supported nutrition-rule version, record ID, date, normalized menu name, status, exact record update date, nutrient IDs, and child-safe educational copy.
- `FileNutrientImpactSidecar` uses an injected Application Support subdirectory, canonical length-delimited revision fields, CryptoKit SHA-256 filenames, strict decode/field validation, and exact matching on load.
- Validation occurs before writes and rejects path traversal/control characters, secret-bearing copy, quantitative per-menu units, medical claims, and allergy-avoidance reversal while allowing opaque punctuation-bearing IDs and ordinary Korean educational prose.
- Installation uses a unique same-directory temporary file, atomic move, immediate exact read-back, and never replaces an existing revision. Concurrent identical bytes are idempotent; conflicting bytes fail. Regular-file/directory checks prevent symlink following, and orphan files are not deleted.
- `NoopNutrientImpactSidecar` is available for nil-snapshot callers without persistence.
- Tests cover round-trip, exact mismatch dimensions, immutable status revisions, corrupt/schema/rule/fingerprint fallback, restart/orphan/stale behavior, validation, concurrency/conflict, symlink safety, no-op behavior, and Core Data v1 schema invariants.

## Warnings

- Existing Xcode logs contain the non-failing `_LottieStub.o` x86_64 architecture warning and expected Core Data error-path diagnostics from persistent-store failure tests; neither affected the passing test results and both are outside Task 5.
- App Intents metadata extraction is skipped because the app has no AppIntents dependency; this is unrelated to Task 5.

No secrets were printed or stored. No upload, submission, browser, or external coordination was performed.

## Review fix round 1

### Scope

- Hardened only `NutrientImpactSidecar.swift` and `NutrientImpactSidecarTests.swift`; the public `NutrientImpactSnapshot` interface remains unchanged.
- Added a strict versioned envelope containing the exact revision fingerprint and a SHA-256 digest of deterministic sorted-key snapshot bytes. Reads reject missing/extra envelope fields, unsupported envelope versions, fingerprint/digest mismatches, and payload-only mutations. This is corruption/tamper evidence, not cryptographic authenticity.
- Compatibility/case normalization now precedes policy scanning, so compatibility-unit and full-width quantity variants are rejected. Clear allergy retry/eating reversals and health/deficiency harm claims are rejected while the canonical educational disclaimer remains accepted. Opaque identifiers may contain ordinary `/` or `\\` punctuation; only actual `.` or `..` path segments and controls are rejected.
- Enforced per-value/count limits, a 20 KiB aggregate UTF-8 string budget, and a 64 KiB encoded/read ceiling. Reads `fstat` before allocation, then consume at most the ceiling plus one byte; malformed and oversized files return `nil`.
- Documented the injected parent chain as a trusted Application Support root. The final directory is opened with `O_DIRECTORY | O_NOFOLLOW`; files are accessed relative to that descriptor with `openat`, `O_NOFOLLOW`, regular-file checks, bounded reads, exclusive `0600` temporary creation, `fsync`, and `renameatx_np(..., RENAME_EXCL)` atomic no-overwrite publication.
- Revision fingerprint strings are NFC-normalized before length-delimited UTF-8 hashing. Stored snapshot strings remain unchanged, and canonically equivalent NFC/NFD revisions resolve to the same hash filename.
- Empty-destination race tests use an initially inactive concurrent start barrier. Identical writers are idempotent; conflicting writers yield exactly one immutable valid winner and leave no temporary residue.

### TDD and verification

- RED — payload-only headline/nutrient/alternative mutations were accepted: 12 tests executed, 3 expected failures.
- RED — compatibility/policy and aggregate/NFC boundary coverage exposed the missing validation/fingerprint behavior. A later completed focused bundle isolated two test-contract boundary corrections (NFC/NFD Swift string equivalence and the aggregate threshold) from simulator infrastructure cancellation.
- GREEN — focused sidecar + persistent schema suite: 28/28 passed, 0 failures, 0 Task 5 runtime warnings (`task5-review-fix-focused-3.xcresult`).
- GREEN — full iOS suite: 432/432 passed, 0 failures, 0 skips (`task5-review-fix-full.xcresult`).
- Native rebuild Python contracts: 32/32 passed.
- `build-for-testing`: passed, including Darwin `openat`/`renameatx_np` portability for the iOS 16 simulator target.
- `git diff --check`: passed.
- Core Data v1/model/migration files and project membership are unchanged from `8a1af43`.

### Infrastructure and warnings

- One focused attempt was cancelled before any `xctest` process appeared because the shared simulator install service entered `simctl diagnose`; this was kept separate from assertion failures. After the result bundle completed, focused and full suites both passed.
- Full-suite xcresult contains one pre-existing QoS warning in `MascotMotionControllerTests.swift`; the focused Task 5 bundle contains no runtime warning. The known non-failing `_LottieStub.o` x86_64 link warning also remains outside Task 5.
- No Task 6 integration, Core Data mutation, UI/assets/release/Android change, upload, submission, or browser action was performed.

## Review fix round 2

### Scope

- Hardened safety-copy scanning by removing invisible Unicode format characters only in the validation view, then applying compatibility and case normalization. Stored snapshot copy remains byte-for-byte unchanged; zero-width and full-width quantitative variants can no longer bypass the policy.
- Replaced broad medical-topic substring rejection with claim-shaped patterns plus explicit safe negations. Actual diagnosis, treatment, deficiency, and harm claims remain rejected, while `영양소 부족을 진단하지 않아요` and the canonical educational disclaimer are accepted.
- Expanded allergy-condition handling for `알레르기가 있는데` and `알레르기가 있으면`: retry/eating encouragement is rejected, while explicit avoidance such as `먹지 않아요` and `피해요` remains valid.
- Added directory durability after atomic exclusive publication: a successful `renameatx_np(..., RENAME_EXCL)` is followed by `fsync(directoryFD)`. A sync failure reports `writeFailed` but deliberately preserves the already-published immutable inode so retries observe the same winner; it never removes another writer's file.

### TDD and verification

- RED — the new durability test failed to compile because the directory-sync seam did not exist (`extra argument 'directorySync' in call`), confirming the missing behavior before implementation.
- RED — a mixed avoidance-plus-retry sentence was initially accepted, proving that a safe-word shortcut could mask later eating encouragement; retry detection now takes precedence.
- GREEN — focused sidecar + persistent schema suite: 30/30 passed, 0 failures (`task5-review-fix-round2-focused-final.xcresult`).
- GREEN — full iOS suite: 434/434 passed, 0 failures (`task5-review-fix-round2-full-final.xcresult`).
- Native rebuild Python contracts: 32/32 passed.
- `git diff --check`: passed.
- Core Data v1 model/migration and project membership are unchanged from `d5b79a4`; only the Task 5 sidecar source, its tests, and this report changed.

### Warnings

- The known non-failing `_LottieStub.o` x86_64 architecture warning remains unrelated to Task 5.
- No Task 6/UI/assets/release/Android change, upload, submission, browser action, or secret handling occurred.

## Review fix round 7 — typed same-meal alternatives

### Scope

- Replaced raw alternative-label input at the snapshot factory boundary with `SameMealAlternativeSelection`, `SameMealAlternative`, and provenance produced only by `SameMealAlternativeSelector` from one `RebuildMealDay`. Selection provenance carries the meal-day fingerprint, date, current menu, and canonical target nutrient IDs.
- The selector excludes the current menu and child-allergy-overlapping items, requires structured nutrient overlap, deduplicates canonical labels after candidate qualification, deterministically prioritizes shared nutrient coverage and target order, and caps the result at two alternatives. The factory rejects stale selection reuse when date, current menu, or target nutrient IDs do not exactly match the requested snapshot.
- Removed menu-label natural-language, quantity, secret, medical, allergy, and action deny-lists. The snapshot keeps its existing `[String]` field, but direct sidecar input now checks only bounded structural invariants: NFC/Unicode space-separator canonicalization, exact canonical representation, controls/format characters/path separators, duplicate labels, and the two-label limit. Ordinary menu labels remain opaque data.
- Made the empty-nutrient fallback neutral, made `finished` copy menu-scoped, and made `allergyAvoided` copy branch on whether typed alternatives exist; when none exist, the suggestion is omitted. The exact disclaimer remains the educational string from `nutrition-rules.json`.
- Tightened `.empty` so only the empty provenance sentinel is canonical. Existing atomic publication, `EEXIST` no-overwrite, fsync, no-follow, digest, NFC fingerprint, size, and concurrency behavior remain unchanged; Task 6 record flow and the Core Data model are untouched.

### TDD and verification

- RED — typed selector/factory tests initially failed to compile because the production API still accepted raw alternative labels and had no provenance-bearing selection type.
- GREEN — focused sidecar + persistent schema suite: 44/44 passed, 0 failures, 0 skips (`build/verification/task-5-7-focused-rerun/Results.xcresult`) on `Codex Task5 iPhone 17 Pro Fresh` (iPhone 17 Pro, iOS 26.5, `DCAC5291-31BF-4515-B31B-1667CD8EB1E3`). This includes exact six-status copy rows, structural-label rejection/acceptance, same-day selector priority/filtering, duplicate-label handling, and three factory provenance-mismatch cases.
- GREEN — native rebuild Python contracts: 32/32 passed (`python3 -m unittest discover -s scripts/tests -p 'test_native_rebuild_contracts.py'`).
- Full iOS rerun at the current shared HEAD executed 448 tests: 447 passed and one pre-existing `RebuildRecordMealUseCaseTests.testLegacyHalfAndMismatchedCanonicalIdentityAreRejectedWithoutWrites()` expectation failed because the half status is now active. The focused sidecar and persistent suites remained green; the unrelated stale half test is being corrected separately before the parent task's final full-suite rerun.
- `git diff --check`: passed before commit.

### Warnings

- The full-suite half-status failure is outside the files in this round and does not exercise `NutrientImpactSidecar`; no sidecar assertion failed. A full-suite rerun is required after the separate half-contract test correction.
- The known non-failing `_LottieStub.o` x86_64 architecture warning remains unrelated to Task 5.
- No Task 6/UI/assets/release/Android change, upload, submission, browser action, or secret handling occurred.

## Review fix round 3

### Scope

- An identical-revision `EEXIST` retry now validates the immutable winner and synchronizes the containing directory before reporting success. Sync failure remains `writeFailed` and preserves the winner and temporary-file cleanup semantics.
- Allergy safety parsing now recognizes generalized Korean risk conditions (`있는데`, `있으면`, `있다면`, `있어도`, `있더라도`, and related forms), isolates the following action text, masks explicit avoidance/negated actions, and rejects any positive eat, taste, or retry cue left behind. Positive cues take precedence in mixed sentences.
- Medical validation now rejects direct grammar-shaped deficiency assertions such as `모자라요`, `부족해요`, and `결핍이에요`, while explicit diagnostic negation and the canonical educational disclaimer remain accepted.

### TDD and verification

- RED — focused tests failed in the new EEXIST resynchronization and safety-copy cases before implementation, including both success/failure sync branches and reviewer-provided allergy/deficiency examples.
- GREEN — focused sidecar + persistent schema suite: 31/31 passed (`task5-review-fix-round3-focused.xcresult`).
- GREEN — full iOS suite: 435/435 passed (`task5-review-fix-round3-full.xcresult`).
- Native rebuild Python contracts: 32/32 passed.
- `git diff --check`: passed. Core Data v1 model/migration and project membership remain unchanged from `a90610d`.

### Warnings

- The known non-failing `_LottieStub.o` architecture warning remains outside Task 5.
- No Task 6/UI/assets/release/Android change, upload, submission, browser action, or secret handling occurred.

## Review fix round 4

### Scope

- Medical-copy validation now recognizes Korean conjugation stems such as `모자라요`, `모자랍니다`, and `모자란 상태` while preserving complete explicit negation and the canonical educational disclaimer.
- Allergy-copy validation now covers conditional and causal particles, masks explicit avoidance/guardian-safe alternatives structurally, and rejects residual eating, tasting, swallowing, or retry cues in mixed unsafe-plus-safe sentences.
- Reviewer copy cases now include per-case assertion diagnostics and additional particle/conjugation variants. Existing `EEXIST` winner validation, directory `fsync`, and fail-closed write behavior remain unchanged.

### TDD and verification

- RED — the focused safety suite isolated rejected copy case 12, `철분이 모자랍니다.`, which was not covered by the prior `모자라` literal shape.
- GREEN — focused sidecar + persistent schema suite: 31/31 passed, 0 failures (`task5-review-fix-round4-focused-final2.xcresult`) on `Codex Task5 iPhone 17 Pro Fresh` (iPhone 17 Pro, iOS 26.5, `DCAC5291-31BF-4515-B31B-1667CD8EB1E3`).
- GREEN — full iOS suite: 435/435 passed, 0 failures (`task5-review-fix-round4-full.xcresult`) on the same fresh simulator.
- Native rebuild Python contracts: 32/32 passed (`python3 scripts/tests/test_native_rebuild_contracts.py`).
- `git diff --check`: passed.
- Core Data v1 model/migration and Xcode project membership are unchanged from `116f5fa`; the round changes are limited to the sidecar source, its tests, and this report.

### Warnings

- The earlier stale simulator runs entered `simctl diagnose` without starting `xctest`; after a scoped CoreSimulator restart, manual installation and both test suites succeeded on the fresh simulator. This was infrastructure evidence, not a test assertion failure.
- The known non-failing `_LottieStub.o` x86_64 architecture warning remains outside Task 5.
- No Task 6/UI/assets/release/Android change, upload, submission, browser action, or secret handling occurred.

## Review fix round 5 — canonical copy catalog

### Scope

- Replaced the brittle Korean regex/NLU safety guesser with a fail-closed `NutrientImpactCopyCatalog`. The sidecar now accepts `headline`, `explanation`, and `disclaimer` only when they exactly equal the deterministic copy for the status and the normalized, known nutrient IDs.
- Added `NutrientImpactSnapshotFactory` so Task 6 can create snapshots without assembling safety-sensitive strings manually. The existing `NutrientImpactSnapshot` fields and schema remain unchanged.
- The catalog covers all six eating statuses. `smelledOnly`, `difficultToday`, and `allergyAvoided` copies describe exploration, pacing, or safety and contain no eating claim; the other statuses use bounded educational encouragement without medical diagnosis, quantitative claims, or pressure to eat. The disclaimer is the exact `educationNotice` from `nutrition-rules.json`.
- Nutrient IDs are allow-listed, deduplicated, and sorted by the contract order. The sidecar additionally requires the stored array to already equal that canonical order, so order/duplicate mutations fail closed. Nutrient names use a neutral ` · ` separator.
- Alternatives are validated as same-meal menu labels, not free-form guidance: the factory applies NFC and Unicode space-separator canonicalization, trims/collapses spaces, permits at most two unique bounded labels, and rejects controls/format/path separators, sentence-ending punctuation, quantity units, secret markers, and clear medical/allergy/action roots. Ordinary labels and punctuation such as `김치·두부`, `고구마 (찐 것)`, and `2026년산 고구마` remain valid.
- Removed the unused `containsForbiddenCopy` and `normalizedSafetyText` regex grammar entirely. Existing atomic temp-file publication, `EEXIST` no-overwrite, fsync, no-follow, digest, NFC fingerprint, byte limits, and concurrency behavior remain unchanged.

### TDD and verification

- RED — the new canonical catalog/factory tests initially failed to compile because `NutrientImpactSnapshotFactory` did not exist.
- GREEN — focused sidecar + persistent schema suite: 34/34 passed, 0 failures, 0 skips (`build/verification/task5-focused-final/Task5Focused.xcresult`) on `Codex Task5 iPhone 17 Pro Fresh` (iPhone 17 Pro, iOS 26.5, `DCAC5291-31BF-4515-B31B-1667CD8EB1E3`). Sidecar: 21/21; persistent schema: 13/13.
- GREEN — full iOS suite: 438/438 passed, 0 failures, 0 skips (`build/verification/task5-full-final/Task5Full.xcresult`) on the same fresh simulator. The existing `_LottieStub.o` x86_64 architecture warning remains non-failing and unrelated.
- GREEN — native rebuild Python contracts: 32/32 passed (`python3 scripts/tests/test_native_rebuild_contracts.py`).
- `git diff --check`: passed after the final test fixture adjustments.

### Warnings

- Task 6 has not yet been wired to the factory in this task; the API is available for that integration. No Core Data model/migration, UI/assets, release metadata, Android behavior, upload, submission, browser action, or secret handling was changed.

## Review fix round 6 — canonical menu grammar and copy quality

### Scope

- Refined all six exact catalog entries to the approved child-facing copy. Finished/half/one-bite messages celebrate the recorded experience, smelled-only keeps exploration separate from nutrition education, difficult-today uses a non-quantitative “may have consumed less” estimate with reassurance, and allergy-avoided prioritizes guardian/school safety without loss or eating advice.
- Added explicit table assertions for every status, including the difficult-today estimate/encouragement requirements and the absence of eating language from smelled-only and allergy-avoided copy. Canonical UTF-8 comparison remains byte-exact and the public snapshot fields are unchanged.
- Replaced permissive alternative validation with a small factory label grammar. Factory inputs normalize NFC and Unicode space separators, trim/collapse spaces, reject duplicate canonical labels, and cap labels at two bounded values. Direct sidecar inputs must already equal that canonical unique representation. Controls/format characters, `/` and `\\`, sentence-ending punctuation, quantity-unit markers (including compatibility/full-width forms), secret markers, and clear medical/allergy/action roots are rejected; ordinary Korean/numeric menu names remain accepted. Quantity matching requires a real unit boundary so labels such as `12 garlic noodles` are not blocked by the `g` unit.
- Every newly rejected direct snapshot uses a unique revision and is checked for exact `.invalidSnapshot` plus unchanged JSON and temporary-artifact sets. Atomic publication, EEXIST/no-overwrite, fsync, no-follow, digest, NFC fingerprint, size, and concurrency guarantees remain intact.

### TDD and verification

- RED — the new exact status table and menu-label canonicalization tests failed against the old copy/label behavior (`task5-review5-red/Task5Review5Red.xcresult`: 2 failures).
- GREEN — focused sidecar + persistent schema suite: 36/36 passed, 0 failures, 0 skips (`build/verification/task5-review6-focused-final/Task5Review6FocusedFinal.xcresult`) on `Codex Task5 iPhone 17 Pro Fresh` (iPhone 17 Pro, iOS 26.5, `DCAC5291-31BF-4515-B31B-1667CD8EB1E3`). Sidecar: 23/23; persistent schema: 13/13.
- GREEN — full iOS suite: 440/440 passed, 0 failures, 0 skips (`build/verification/task5-review6-full-final/Task5Review6FullFinal.xcresult`) on the same fresh simulator.
- GREEN — native rebuild Python contracts: 32/32 passed (`python3 scripts/tests/test_native_rebuild_contracts.py`).
- `git diff --check`: passed.

### Warnings

- The known non-failing `_LottieStub.o` x86_64 architecture warning remains unrelated to Task 5.
- No Task 6/UI/assets/release/Android change, upload, submission, browser action, or secret handling occurred.
