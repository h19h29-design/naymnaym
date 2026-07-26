# Task 5 report — seven-stage mascot growth

## Status

DONE

The seven-stage growth policy, mascot assets, persisted progress views, and
collection are implemented on iOS and Android. No deployment or push was
performed.

## Shared contract and art

- Added the canonical growth contract with thresholds
  `[0, 80, 180, 320, 500, 720, 1000]` and the exact seven
  `PlayerProgress.levelTitles`.
- The canonical contract and both runtime mirrors are byte-identical.
- Removed the conflicting legacy visual-title list.
  `GrowthCharacterAssets.stageTitle(for:)` now delegates to
  `PlayerProgress.title(for:)`.
- Produced levels 2–7 from each immutable `Squirrel_Growth_Level_N` source.
  Every level contains eleven semantic parts and verified REST, BLINK, and
  CELEBRATE composites on a 1254×1254 canvas with anchor `(627, 1128)`.
- Registered explicit level 1–7 descriptors, hashes, semantic fallback maps,
  and native resource identifiers on both platforms. There is no reflection,
  runtime identifier lookup, copied level-1 definition, or cross-level
  fallback.
- The validator locks immutable source identity, unique cross-level hashes,
  transparent RGB, meaningful neutral mouths, and all three acceptance
  composites.

## Persisted growth experience

- Core Data and Room read positive XP events only, ordered by
  `occurredAt DESC, id DESC`, with a hard maximum of 20 records.
- Home, Growth, and Collection derive level from persisted total XP through
  the shared `GrowthPolicy`; stale legacy level state is not combined with
  persisted XP.
- Growth and Collection are real tab destinations on both platforms and reload
  when activated.
- The Growth screen order is current rig, level/XP progress, next unlock, then
  recent positive events.
- Meal labels are derived only from valid canonical `meal:` event IDs. Legacy
  UUID `sourceRecordID` values remain generic, and reconciliation is labeled
  explicitly.
- Unlocked collection entries use full-color verified REST art. Locked entries
  use a warm solid silhouette and a textual lock label; grayscale is not used.
- Cards use opaque cream/white surfaces so later detailed forest backgrounds
  cannot reduce readability.

## iOS static-art memory gate

- Added a checksum- and dimension-verified REST-only thumbnail loader/cache.
- Collection and next-unlock previews decode one REST frame per visible level
  instead of loading all three animation keyframes.
- Hashing, source-dimension validation, and decoding run through a detached
  loading worker rather than the main actor.
- A static preview is downsampled to at most 256 px only after its original
  1254×1254 source and SHA-256 have been verified.
- The static cache is a byte-cost LRU capped at 2 MiB. Full keyframes and
  semantic fallback layers share one heavy slot for the active level.
- Focused tests prove off-main execution, thumbnail dimensions, byte-cost
  eviction, and single-active-level full/fallback eviction.
- Silent `try?` and legacy `Squirrel_Growth_Level_N` fallback rendering were
  removed. Loading is explicit, and failures expose an accessible retry state.

## Post-review hardening

- `MascotRestArtLoader` now accepts the requested level per load and rejects
  stale completions. Changing a card from level 1 to level 4 loads level 4
  rather than keeping the `@StateObject` initializer's original level.
- `MascotRigView` renders only checksum-verified keyframes or verified
  semantic fallback layers. If both fail, it exposes an independently
  actionable retry button instead of silently showing a legacy asset.
- Growth, Collection, and Today cards no longer combine away nested retry
  actions with a fixed parent accessibility label.
- Canonical meal copy now requires a real Gregorian `yyyy-MM-dd` date and an
  already `trimAndLowercase` menu identity. Impossible dates, surrounding
  whitespace, and uppercase ASCII identities remain truthful generic growth
  records. Valid legacy `half` identities display `절반 먹었어요`.
- The warm `#B87548` tone is now silhouette-only. Locked supporting text uses
  Forest 700 and passes WCAG normal-text contrast on the warm locked surface.
- Android replaced both unbounded mascot maps with deterministic
  access-ordered caches: one active full rig/fallback level and a 2 MiB static
  thumbnail cache. Android also verifies the 1254×1254 source before
  downsampling static art to 256 px.

## Second-review cache serialization

- iOS now uses one generation-guarded heavy cache for either the current
  three-frame rig or the current semantic fallback. The two representations
  cannot remain cached together.
- Requests for the same representation and level coalesce into one task.
  A new key cancels and removes older in-flight work, and an older completion
  cannot replace the newest cached value.
- Already-cancelled callers are rejected before cache generation, eviction, or
  loading. The detached image worker checks cancellation before and after
  decoding and receives caller cancellation.
- REST and rig loaders treat cancellation as a silent transition rather than a
  load error. A cancelled keyframe request cannot start semantic fallback and
  cancel the next level's active request.
- Growth and rig views render assets only when `loadedLevel` equals the
  requested level, so a level transition cannot expose the prior character for
  one frame.
- Semantic fallback files retain their immutable SHA and original 1254×1254
  dimension checks, then decode to a maximum 512×512 transparent canvas.
  Layer order remains the canonical eleven-part order.
- Diagnostics use decoded byte cost. The active full rig is bounded below
  20 MiB in the fixture and the eleven-layer fallback below 12 MiB, both under
  the 24 MiB heavy-cache ceiling.

## TDD evidence

The following expected RED states were observed before their implementations:

- iOS policy/repository tests failed on missing `GrowthPolicy`,
  `recentPositiveEvents`, and truthful event presentation.
- Android policy/repository and screen tests failed on missing growth domain,
  catalog, and real tab content.
- The seven-level iOS catalog test failed because the explicit catalog did not
  exist.
- Canonical-title parity failed with the old titles including
  `새싹`, `꼬마 모험가`, and `숲의 수호자`.
- The REST memory test failed because `restImage`,
  `cachedRestImageCount`, and `cachedRigImageSetCount` did not exist.
- The truthful REST error test failed because `MascotRestArtLoader` did not
  exist.
- The level-transition test failed because the REST loader required a fixed
  initializer level.
- The verified-failure tests failed because `MascotRigLoader` and its explicit
  retry state did not exist.
- Canonical meal parity failed on `half`, impossible `2026-02-30`, surrounding
  menu whitespace, and uppercase `SPINACH` identities on both platforms.
- Locked-text contrast tests failed before the dedicated silhouette/text
  palette existed.
- iOS cache tests failed before `restThumbnail`, byte-cost diagnostics, and
  single-active-level eviction existed.
- The off-main worker test failed before `MascotImageLoadingWorker` existed.
- Android cache tests failed before `BoundedMascotCache` existed.
- The second-review cache tests failed while rig and fallback could both retain
  level 4 and while fallback images still decoded at 1254 px:
  `test_sim_2026-07-26T07-20-39-454Z_pid85607_28ed53cb.log`.
- Heavy-cost assertions failed to compile before diagnostics exposed
  `heavyCost`:
  `test_sim_2026-07-26T07-21-01-137Z_pid85607_d82ac9dd.log`.
- Generation, same-key coalescing, different-key cancellation, and detached
  worker propagation tests failed before `LatestActiveAssetCache` and worker
  cancellation hardening.
- Four cancellation regressions failed before loaders handled
  `CancellationError` explicitly: the cancelled cache caller replaced its
  predecessor, REST exposed `invalidImage`, rig entered fallback, and stale
  level 1 work replaced level 4 with `fallback-4`:
  `test_sim_2026-07-26T07-25-02-652Z_pid85607_bb92a066.log`.

Focused GREEN results:

- iOS policy, repository ordering/copy, and title parity: 9/9.
- iOS mascot motion, transition, verified fallback/error, worker, and bounded
  cache tests: 25/25.
- iOS canonical meal and locked-text contrast tests: PASS.
- Android growth policy/repository/catalog/UI compilation: PASS.
- Android canonical meal, locked-text contrast, and deterministic count/byte
  eviction tests: PASS.
- Android persisted-home-level instrumentation: 3/3.
- Second-review heavy-cache and 512 px fallback tests: 2/2.
- Cancellation and stale-active-key regressions: 4/4.
- Final iOS mascot motion/cache/loader suite: 36/36; warnings 0, errors 0.

## Final verification

- `python3 -m unittest -v scripts.tests.test_validate_mascot_rig`
  - 11/11 PASS.
- `python3 scripts/validate-mascot-rig.py --root art/mascot-rig`
  - `77 parts: PASS`.
- `python3 scripts/tests/test_native_rebuild_contracts.py`
  - 23/23 PASS.
- `python3 scripts/validate-native-rebuild-contracts.py`
  - PASS.
- `bash scripts/sync-native-rebuild-contracts.sh` and runtime `cmp`
  - PASS; both growth-policy mirrors are byte-identical.
- XcodeBuildMCP `test_sim`
  - 306 passed, 0 failed, 0 skipped; warnings 0, errors 0.
  - final build log:
    `~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-26T07-34-00-269Z_pid85607_073c0b29.log`
- Android:
  - `testDebugUnitTest connectedDebugAndroidTest assembleDebug`
  - BUILD SUCCESSFUL.
  - JVM: 142/142 passed.
  - connected API-35 emulator: 33/33 passed.
  - The existing ASCII temporary build-output redirect was used because Kotlin
    test output is unreliable under the Korean workspace path. It was not
    committed.
- `plutil -lint NaymNaymLevelUp.xcodeproj/project.pbxproj`
  - OK.
- `git diff --check`
  - no errors.

## Visual QA

`art/mascot-rig/visual-comparison-levels-01-04-07.png` contains three exact
390×844 panels in one 1170×844 comparison. Levels 1, 4, and 7 use the same
300×300 source projection and the same `(627, 1128)` anchor baseline. Visual
inspection confirms consistent foot baseline and scale while preserving the
intended increase in costume detail. The comparison was re-opened and
re-inspected after the cache hardening. A temporary QA sheet also rendered the
runtime-equivalent 512 px semantic REST stack beside `composite-rest` for
levels 1, 4, and 7. All pairs kept canonical layer overlap, transparent
full-square alignment, and the same foot baseline. The temporary QA artifact
was removed after inspection; approved source art was not changed.

## Figma

Task 5 is tracked in the existing Figma file and was not duplicated:

`https://www.figma.com/design/PzhrBaw0BuAMNTX4BPyfsM?node-id=46-2`
