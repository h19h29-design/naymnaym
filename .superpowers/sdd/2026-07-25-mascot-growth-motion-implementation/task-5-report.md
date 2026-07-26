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

- Added a checksum- and dimension-verified REST-only loader/cache.
- Collection and next-unlock previews decode one REST frame per visible level
  instead of loading all three animation keyframes.
- The focused cache test proves one REST cache entry and zero full-rig cache
  entries after a static level load.
- Silent `try?` and legacy `Squirrel_Growth_Level_N` fallback rendering were
  removed. Loading is explicit, and failures expose an accessible retry state.

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

Focused GREEN results:

- iOS policy, repository ordering/copy, and title parity: 9/9.
- iOS REST-only cache and explicit error state: 2/2.
- Android growth policy/repository/catalog/UI compilation: PASS.
- Android persisted-home-level instrumentation: 3/3.

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
  - 287 passed, 0 failed, 0 skipped; warnings 0, errors 0.
  - final build log:
    `~/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/logs/test_sim_2026-07-26T06-23-38-568Z_pid42459_403f8754.log`
- Android:
  - `testDebugUnitTest connectedDebugAndroidTest assembleDebug`
  - BUILD SUCCESSFUL.
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
intended increase in costume detail.

## Figma

Task 5 is tracked in the existing Figma file and was not duplicated:

`https://www.figma.com/design/PzhrBaw0BuAMNTX4BPyfsM?node-id=46-2`
