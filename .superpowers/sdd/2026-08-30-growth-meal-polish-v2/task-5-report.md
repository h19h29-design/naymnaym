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
