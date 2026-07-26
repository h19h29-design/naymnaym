# Living forest scene QA

## Approved art and packaging

The production scene uses five aligned `1290×2796` masters in this exact
back-to-front order: `sky`, `distantTrees`, `midgroundTrees`,
`foregroundLeaves`, and `ground`. The sky is opaque RGB; every other layer is
RGBA with transparent pixels retained in the outer 12 px band. The dedicated
validator pins every master, reference, REST composite, maximum-motion
composite, and runtime derivative by SHA-256.

The two approval frames are:

- REST: `art/forest-scene/home/acceptance-rest.png`
- Maximum motion: `art/forest-scene/home/acceptance-max-motion.png`

Both include the production `1.04` foreground overscan. Visual review found no
transparent seam, magenta matte, character, copy, control, icon, or food baked
into the background.

Only `860×1864` derivatives ship in either app. The iOS
`Resources/ForestScene/Home` folder contains exactly these five files, and the
Android copies are byte-identical in `drawable-nodpi`.

| Runtime file | Packaged bytes per platform | SHA-256 |
| --- | ---: | --- |
| `forest_home_sky.png` | 2,507,105 | `31269847c3ea3825cfb0622c642bbf7bf58cd85f49c168a4b77864cb134151c6` |
| `forest_home_distant_trees.png` | 567,133 | `9c2e598b7aaad3240a97930a796b499769950a3dcd3569e89fd728319d1e56f1` |
| `forest_home_midground_trees.png` | 1,405,400 | `19cd4380674504a333c31573432562ab3e3cb8730e7f2283c15d0e8c0b3e2dbf` |
| `forest_home_foreground_leaves.png` | 628,768 | `66893d6c0913a36962ec2b2855506bb26e47a0024bc65ceb662bf5b0e6759c28` |
| `forest_home_ground.png` | 285,098 | `5468374dce57202cec48e94e11015b339f15140b458b183320239f6653e8b23f` |
| **Total** | **5,393,504** | byte-identical on iOS and Android |

No master or acceptance composite is packaged in either runtime bundle.

## Motion, pause, and memory contract

One deterministic eight-second triangle cycle is shared by both platforms:

| Time | Progress | Distant Y | Midground Y | Foreground X / Y |
| ---: | ---: | ---: | ---: | ---: |
| 0 s | 0% | 0 | 0 | 0 / 0 |
| 2 s | 50% | -1 | -2 | +3 / -1.5 |
| 4 s | 100% | -2 | -4 | +6 / -3 |
| 6 s | 50% | -1 | -2 | +3 / -1.5 |
| 8 s | 0% | 0 | 0 | 0 / 0 |

Sheet presentation, an inactive Today tab, and an inactive app each freeze the
same monotonic clock. Resume subtracts paused time, so the scene does not jump.
Reduce Motion fixes every transform at zero and schedules no display/frame
callback.

On iOS, forest and mascot runtime sampling use an injectable time source whose
production implementation reads `ProcessInfo.processInfo.systemUptime`.
`TimelineView` dates trigger redraws only; deterministic tests advance the
injected uptime directly, so wall-clock adjustments cannot reset either motion.

Decoded bounds use four bytes per pixel:

- Forest: `860 × 1864 × 4 × 5 = 32,060,800` bytes (`30.576 MiB`), below
  `32 MiB`.
- Active three-frame mascot: `18,870,192` bytes (`17.996 MiB`).
- Combined: `50,930,992` bytes (`48.572 MiB`), below `52 MiB`.

Android decodes the five layers sequentially on `Dispatchers.IO`, publishing at
most one new texture per frame. An API-35 focused reinstall/run after this
change produced no target-process `Skipped N frames` Choreographer entry. iOS
loads only the validated runtime derivatives. A release-grade cold-launch
Instruments/Perfetto trace remains a release-candidate gate rather than a claim
made by this source commit.

## Contrast and native controls

All copy and the mascot stage sit on opaque `cream50` surfaces. Verified WCAG
contrast ratios are:

| Pair | Ratio |
| --- | ---: |
| `ink900` / `cream50` | 13.28:1 |
| `forest700` / `cream50` | 7.30:1 |
| `muted600` / `cream50` | 4.90:1 |
| `cream50` copy / `muted600` disabled button | 4.90:1 |

Android navigation and decoration use Material icons and native circle shapes;
the production path contains none of the former `🌿`, `📈`, `📚`, `✨`, or
`●` text stand-ins.

## Native viewport evidence

Every file below is a full-resolution screenshot from the real seeded debug app,
captured after the final source and runtime assets were installed. The iOS runs
used iOS 26.5 and the Android runs used the API-35
`naym_android_test` AVD.

Normal iOS captures used `UICTContentSizeCategoryM` and
`ReduceMotionEnabled=0`. The 200% acceptance captures used
`UICTContentSizeCategoryAccessibilityL` (the approximately 2× accessibility
body scale) and were scrolled until the primary action was fully visible.
Reduce Motion captures used the real system `ReduceMotionEnabled=1` preference.

Normal Android captures used `font_scale=1.0` and
`animator_duration_scale=1.0`. Android 200% captures used
`font_scale=2.0`, and Reduce Motion used
`animator_duration_scale=0`. The final capture APK is 65,808,716 bytes with
SHA-256
`1f58b316df8dbb7e937d64deaf112f17500f7e8c84036369313dc8fb0197e32d`.

| Viewport and device | REST | Maximum motion | Recorder-sheet pause | Reduce Motion | 200% text |
| --- | --- | --- | --- | --- | --- |
| compact iPhone — iPhone SE (3rd generation), 375×667 logical / 750×1334 px | [file](forest-scene/ios-compact-rest.png)<br>2026-07-27 00:06:44 KST | [file](forest-scene/ios-compact-max-motion.png)<br>00:06:48 KST | [file](forest-scene/ios-compact-recorder-pause.png)<br>00:07:37 KST | [file](forest-scene/ios-compact-reduce-motion.png)<br>00:07:52 KST | [file](forest-scene/ios-compact-text-200.png)<br>00:08:33 KST |
| iPhone 390×844 — iPhone 14, 1170×2532 px | [file](forest-scene/ios-390-rest.png)<br>2026-07-27 00:04:06 KST | [file](forest-scene/ios-390-max-motion.png)<br>00:04:10 KST | [file](forest-scene/ios-390-recorder-pause.png)<br>00:04:46 KST | [file](forest-scene/ios-390-reduce-motion.png)<br>00:05:26 KST | [file](forest-scene/ios-390-text-200.png)<br>00:06:06 KST |
| iPhone Pro Max — iPhone 17 Pro Max, 440×956 logical / 1320×2868 px | [file](forest-scene/ios-pro-max-rest.png)<br>2026-07-27 00:09:09 KST | [file](forest-scene/ios-pro-max-max-motion.png)<br>00:09:13 KST | [file](forest-scene/ios-pro-max-recorder-pause.png)<br>00:09:33 KST | [file](forest-scene/ios-pro-max-reduce-motion.png)<br>00:09:47 KST | [file](forest-scene/ios-pro-max-text-200.png)<br>00:10:23 KST |
| Android 360×800 logical — 1080×2400 px at 480 dpi | [file](forest-scene/android-360-rest.png)<br>2026-07-27 00:06:03 KST | [file](forest-scene/android-360-max-motion.png)<br>00:06:08 KST | [file](forest-scene/android-360-recorder-pause.png)<br>00:06:23 KST | [file](forest-scene/android-360-reduce-motion.png)<br>00:06:50 KST | [file](forest-scene/android-360-text-200.png)<br>00:07:44 KST |
| Android large — approximately 411×914 logical / 1440×3200 px at 560 dpi | [file](forest-scene/android-large-rest.png)<br>2026-07-27 00:08:20 KST | [file](forest-scene/android-large-max-motion.png)<br>00:08:25 KST | [file](forest-scene/android-large-recorder-pause.png)<br>00:10:03 KST | [file](forest-scene/android-large-reduce-motion.png)<br>00:10:17 KST | [file](forest-scene/android-large-text-200.png)<br>00:11:02 KST |

The real recorder sheet remained open for each pause proof. A second screenshot
two seconds later was byte-identical on all five viewports:

- compact iPhone:
  `8bc507a370dec01231ebfa18dc18a8ac170608f850cf6e3f979010641a574cc0`
- iPhone 390×844:
  `5565930c25ce25c4550a2084d419bb77563657ee01b8da54d724dce12f37a19a`
- iPhone Pro Max:
  `cbacdc3aca3ca54244225e4714f4381b536903e6fc273e6cf214bb7bdd34e401`
- Android 360×800:
  `6aafcedd8c1f023ab4b5ba3a347c9b35e681aa8c7eaf848a3b851c45bf97a3ae`
- Android large:
  `7a143bd50d28a9eb13a40172a3befc6b4aaf146107bcbb804af1918c36e688bc`

The same two-second byte-identity check passed with the real Reduce Motion
setting:

- compact iPhone:
  `b78f29bea893ba2a56b16c1f43497bde9cfc6129fc142305fc0f0c163c41f6c0`
- iPhone 390×844:
  `60e62189daf1dea43cc9db160b524b9b7578c3864f40861e55d2fa401c56c2de`
- iPhone Pro Max:
  `c15abb28f9fc7e070d34a7dcfba5fa7072d763b70b4fce5cfd2222dc6d8da7a0`
- Android 360×800:
  `544059a130b563e80ee609f66b02157e86f1d736fa0eedfdc2d3f0f21b0e968e`
- Android large:
  `ce8ed2bf23c55135d2cbcab574fa8202176181667104387211894e47944687e8`

At Android 200%, the `오늘의 점심` heading and `저장된 급식` source label
remain vertically separated: 8 dp on both viewports (24 px at 480 dpi and
28 px at 560 dpi). The primary action is fully visible at bounds
`1825..1946` on the 360×800 capture and `2511..2653` on the large capture.
The three iOS accessibility-size captures likewise show the meal heading,
source, menu copy, and full primary action without collision or clipping after
scrolling.

Visual inspection of all 25 committed captures found no transparent scene edge,
foreground halo, copy-over-leaves contrast regression, character obstruction,
or primary-action overlap. No iPad capture is required because
`TARGETED_DEVICE_FAMILY` remains `1`.

<details>
<summary>Committed capture SHA-256 manifest</summary>

```text
ios-compact-rest                 5b5433b0bed9194926acd74c06a859c708f60634df4f0bdee31d76464eb95158
ios-compact-max-motion           dff5f65a46012c1b03b5a6b20880a28c68a1f218421a53dbbf3843c31399235d
ios-compact-recorder-pause       8bc507a370dec01231ebfa18dc18a8ac170608f850cf6e3f979010641a574cc0
ios-compact-reduce-motion        b78f29bea893ba2a56b16c1f43497bde9cfc6129fc142305fc0f0c163c41f6c0
ios-compact-text-200             0b928d8d1d60ededfcf6e9dfb37593c2ee4ca758917ad48dce870af74125f07e
ios-390-rest                     774feef1c3ef3e646e1faac60b618fd88fe28a938a7e776be6f1148fbc757f1e
ios-390-max-motion               737af32e19aedf88ae9d8a56b69ce9ed8ece28dfccdb394736b627aa16ddce72
ios-390-recorder-pause           5565930c25ce25c4550a2084d419bb77563657ee01b8da54d724dce12f37a19a
ios-390-reduce-motion            60e62189daf1dea43cc9db160b524b9b7578c3864f40861e55d2fa401c56c2de
ios-390-text-200                 9b917ede4dbddedd106bfbbb8fe94fd4faa93f0695ca6d4debf85f32c1362642
ios-pro-max-rest                 7e9b821560bd0309c56a0a37f87f77d5ab451c1a5f4ddafebc542e5693d27244
ios-pro-max-max-motion           2d98ffc3affbcae6834567308e34af3dce47219fc378eecae1cde86349e4b784
ios-pro-max-recorder-pause       cbacdc3aca3ca54244225e4714f4381b536903e6fc273e6cf214bb7bdd34e401
ios-pro-max-reduce-motion        c15abb28f9fc7e070d34a7dcfba5fa7072d763b70b4fce5cfd2222dc6d8da7a0
ios-pro-max-text-200             52cb22a731ee6530bd502fc523f5e8097211b96d4b5e04abcae5a3232f51778a
android-360-rest                 53c4e2383c0aa80b00b51e1b2bde7b8a9d6fe5f95df2e2604705ff42036e460b
android-360-max-motion           20da79a517b8a0ffd62b4f69558bd72826354d650d7c8a98a1720043370d82a6
android-360-recorder-pause       6aafcedd8c1f023ab4b5ba3a347c9b35e681aa8c7eaf848a3b851c45bf97a3ae
android-360-reduce-motion        544059a130b563e80ee609f66b02157e86f1d736fa0eedfdc2d3f0f21b0e968e
android-360-text-200             91fa8774c2044e7da20d3cc8e1ce340e0a01d1f7d48d5ee7bded8851f14269a7
android-large-rest               61cd958b55e4e188d0745a9fbf29e9f8a46d4471429723a787e95ee02cd1547a
android-large-max-motion         c5cbedc4f563f7f92d51f200a43acce1d000cccc99322813d58f237d65f62d44
android-large-recorder-pause     7a143bd50d28a9eb13a40172a3befc6b4aaf146107bcbb804af1918c36e688bc
android-large-reduce-motion      ce8ed2bf23c55135d2cbcab574fa8202176181667104387211894e47944687e8
android-large-text-200           47e70567742f733ba0abc7e377717d9978e1098de6f5f44bb245275d3203bcdc
```

</details>

## Automated gate

Fresh final results after all review corrections:

- Forest asset validator: PASS — forest `30.576 MiB`, combined
  `48.572 MiB`, and 10 checksum-matched runtime copies.
- Native contract validator: PASS.
- Native contract sync: PASS.
- Python validator suites: 45/45 PASS in 96.400 seconds.
- iOS XcodeBuildMCP `test_sim`: 353/353 PASS, 0 failures, 0 skips,
  0 warnings, and 0 errors in 10.32 seconds.
- Android JVM tests: 166/166 PASS, including
  `processAssetCacheLoadsEachLayerOnlyOnce`.
- Android API-35 instrumentation: 63/63 PASS, including inactive-Today pointer
  isolation and fresh-XP reload coverage for both Growth and Collection
  tab re-entry.
- Android `assembleDebug`: PASS. APK SHA-256:
  `4b32a381d24734e4e2217d7cd09a08f20325761423e871aaf296eb123ab2283c`.
- `plutil -lint` and `git diff --check`: PASS.
- `TARGETED_DEVICE_FAMILY = 1` remains unchanged in every build
  configuration.

The API-35 cold reinstall/run after moving layer decoding off the main thread
produced no target-process `Skipped N frames` Choreographer entry. The iOS
simulator does not support the Animation Hitches instrument, so this ledger does
not invent a hardware frame-pacing number; a release-device Instruments trace
remains an explicit release-candidate gate.

## Figma record

The approved scene system is stored once in Figma file
`PzhrBaw0BuAMNTX4BPyfsM` as the `living-forest-scene` board at node `65:2`.
The board contains the two approved scene states and all five actual production
layer images. Final plugin validation found exactly one board and one of every
stable named node, seven nonempty IMAGE fills, only `Noto Sans KR`, no missing
fonts, no zero-sized or placeholder nodes, and no visible clipping in the
1500×1510 final export. Its status and footer record the final iOS, Android, and
Python gate counts.

## Independent scoped re-review

The same reviewer who raised the original four P1 findings re-reviewed the final
uncommitted Task 7 diff and returned:

> APPROVED — all four prior P1 findings addressed; no new Critical/Important
> findings

The approval covered these corrections:

1. Growth and Collection are conditionally composed when active, and separate
   API-35 tests prove that both tabs reload newly persisted XP on re-entry.
2. Android forest PNGs decode sequentially on `Dispatchers.IO`, reuse a
   process-level cache, publish at most one new texture per frame, and the
   focused cold run has no target-process skipped-frame entry.
3. The disabled primary action explicitly uses `cream50` content on
   `muted600`, preserving the verified 4.90:1 pair.
4. The final QA ledger contains package/memory evidence plus all 25 real
   viewport captures for REST, maximum motion, recorder pause, Reduce Motion,
   and 200% text.

A separate whole-branch reviewer then found two Important runtime risks:
inactive Android route pointer input and wall-clock-based iOS motion sampling.
Both were reproduced with RED tests, corrected with an inactive-route pointer
gate and injected monotonic uptime, and re-reviewed by that same reviewer. The
final scoped verdict was `APPROVED`, with every prior Important and Minor item
addressed and no new Critical or Important finding.
