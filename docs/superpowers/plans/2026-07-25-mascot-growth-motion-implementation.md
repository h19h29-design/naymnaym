# 냠냠레벨업 캐릭터·성장·모션 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 현재 다람쥐 외형을 유지하면서 7단계 캐릭터를 실제 파츠 리깅으로 다시 구성하고, 상황별 모션·성장·도감·인트로 로고를 양 플랫폼에 구현한다.

**Architecture:** 모든 캐릭터 단계는 1254×1254 공통 캔버스와 동일한 파츠 이름을 사용한다. 11개 파츠의 알파는 의미론적 모션 가중치 맵이며, 승인된 축하 포즈는 이 가중치 맵을 사용한 심리스 소프트 스키닝 키프레임으로 렌더링한다. 앱은 검증·체크섬 고정된 포즈 키프레임과 표정 레이어를 소비한다. 모션 타이밍과 키프레임은 플랫폼 중립 JSON으로 관리하고, SwiftUI와 Compose가 같은 상태를 재생한다.

**Tech Stack:** PNG RGBA assets, Python 3 validator, JSON motion spec, SwiftUI animation, Compose animation, XCTest, JUnit/Compose UI Test

## Global Constraints

- 비주얼 방향은 `살아있는 숲속 모험`이다.
- 캐릭터 외형은 `원형 유지형`이며 얼굴·비율·새싹·잎사귀 스카프·주황/크림 색을 바꾸지 않는다.
- 기본 모션 성격은 `통통 튀는 게임 친구`지만 대기 상태를 계속 반복 점프시키지 않는다.
- 기존 7단계 원화는 교체 검증이 끝날 때까지 삭제하거나 덮어쓰지 않는다.
- 캐릭터 파츠는 모두 1254×1254 RGBA PNG, 동일 원점, 투명 배경을 사용한다.
- 인트로 로고는 `냠냠 → 레벨업 → 빛` 순서로 한 번만 재생한다.
- Reduce Motion에서는 위치 이동과 빛 이동을 제거한다.

## Target File Map

### 공통

- `contracts/native-rebuild/v1/mascot-rig.json`: 레벨별 파츠와 앵커
- `contracts/native-rebuild/v1/mascot-motion.json`: 상태별 키프레임과 시간
- `scripts/validate-mascot-rig.py`: 파일·크기·알파·파츠 완전성 검증
- `art/mascot-rig/level-01` … `level-07`: 제작 마스터 및 검토 이미지
- `art/forest-scene/home`: 아이 홈의 다섯 레이어 숲 배경

### iOS

- `NaymNaymLevelUp/Resources/MascotRig/level_01` … `level_07`: 앱용 파츠
- `NaymNaymLevelUp/Rebuild/Mascot/MascotRigModel.swift`
- `NaymNaymLevelUp/Rebuild/Mascot/MascotRigView.swift`
- `NaymNaymLevelUp/Rebuild/Mascot/MascotMotionController.swift`
- `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- `NaymNaymLevelUp/Rebuild/Growth/GrowthView.swift`
- `NaymNaymLevelUp/Rebuild/Growth/CollectionView.swift`
- `NaymNaymLevelUp/Rebuild/Onboarding/RebuildIntroView.swift`
- `NaymNaymLevelUp/Rebuild/Child/ForestSceneView.swift`

### Android

- `android/app/src/main/res/drawable-nodpi/mascot_l01_*` … `mascot_l07_*`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRigModel.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRig.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotMotionController.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthDomain.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/CollectionScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestScene.kt`

---

### Task 1: 캐릭터 리그 계약과 에셋 검증기

**Files:**
- Create: `contracts/native-rebuild/v1/mascot-rig.json`
- Create: `contracts/native-rebuild/v1/mascot-motion.json`
- Create: `scripts/validate-mascot-rig.py`
- Create: `scripts/tests/test_validate_mascot_rig.py`

**Interfaces:**
- Produces: exact part names `tailBack`, `body`, `scarf`, `head`, `armLeft`, `armRight`, `eyesOpen`, `eyesClosed`, `mouthNeutral`, `mouthSmile`, `sprout`
- Produces: motion states from `domain-contract.json`
- Validates: 7 levels × 11 RGBA PNGs at 1254×1254

- [ ] **Step 1: Write the failing validator test**

```python
class MascotRigValidatorTests(unittest.TestCase):
    def test_reports_missing_parts_for_every_level(self):
        result = subprocess.run(
            ["python3", "scripts/validate-mascot-rig.py", "--root", self.empty_root],
            cwd=ROOT, capture_output=True, text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("level-01/tailBack.png", result.stderr)
        self.assertIn("level-07/sprout.png", result.stderr)
```

- [ ] **Step 2: Run the test**

Run: `python3 scripts/tests/test_validate_mascot_rig.py`

Expected: FAIL because the validator does not exist.

- [ ] **Step 3: Implement exact rig and motion specs**

Each level entry:

```json
{
  "level": 1,
  "canvas": {"width": 1254, "height": 1254},
  "parts": [
    "tailBack", "body", "scarf", "head", "armLeft", "armRight",
    "eyesOpen", "eyesClosed", "mouthNeutral", "mouthSmile", "sprout"
  ],
  "anchor": {"x": 627, "y": 1128}
}
```

`mascot-motion.json` must define:

```json
{
  "idle": {"durationMs": 6000, "loop": true},
  "tapReaction": {"durationMs": 420, "loop": false},
  "mealSuccess": {"durationMs": 1400, "loop": false},
  "levelUp": {"durationMs": 3000, "loop": false},
  "comfort": {"durationMs": 1200, "loop": false},
  "reducedMotion": {"durationMs": 250, "loop": false}
}
```

The Python validator must parse PNG headers with `struct`, require dimensions 1254×1254 and PNG color type 6, and check every path.

- [ ] **Step 4: Run validator unit tests**

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Expected: `native-rebuild-contract-sync: PASS`.

Run: `python3 scripts/tests/test_validate_mascot_rig.py`

Expected: PASS using generated temporary RGBA fixtures.

- [ ] **Step 5: Commit**

```bash
git add contracts/native-rebuild/v1/mascot-rig.json contracts/native-rebuild/v1/mascot-motion.json scripts/validate-mascot-rig.py scripts/tests/test_validate_mascot_rig.py NaymNaymLevelUp/Resources/RebuildContracts android/app/src/main/assets/rebuild-contracts
git commit -m "test: define mascot rig contract"
```

### Task 2: 레벨 1 프로덕션 리그 제작과 합성 승인

**Files:**
- Create: `art/mascot-rig/level-01/source-notes.md`
- Create: `art/mascot-rig/level-01/reference-flat.png`
- Create: `art/mascot-rig/level-01/{tailBack,body,scarf,head,armLeft,armRight,eyesOpen,eyesClosed,mouthNeutral,mouthSmile,sprout}.png`
- Create: `art/mascot-rig/level-01/composite-rest.png`
- Create: `art/mascot-rig/level-01/composite-blink.png`
- Create: `art/mascot-rig/level-01/composite-celebrate.png`

**Interfaces:**
- Produces: approved level-1 part set consumed by both apps
- Guarantees: no visible seams at rest, blink, arm raise, tail sway, and 8% body squash

- [ ] **Step 1: Copy the immutable reference**

Copy `Squirrel_Growth_Level_1.png` to `reference-flat.png`; record its SHA-256 in `source-notes.md`. Do not modify the original asset.

- [ ] **Step 2: Produce the 11 exact semantic parts on the shared canvas**

For every part, paint the covered area that becomes visible during motion rather than cutting only visible pixels. Their alpha channels are the semantic soft-skinning weights used to render seam-free approved keyframes; they are not a promise that an unfeathered rigid cutout composition is visually acceptable. Preserve the reference face proportions, outline, color, leaf scarf, and sprout. Export straight-alpha RGBA PNG without color-profile conversion.

- [ ] **Step 3: Render the three acceptance composites**

Use a deterministic composition script or graphics editor positions from `mascot-rig.json`:

- `composite-rest.png`: exact rest pose
- `composite-blink.png`: closed eyes only; source mouth, nose, and muzzle remain exact
- `composite-celebrate.png`: seam-free semantic part-weight-map soft-skinning keyframe with both arms raised 12°, tail rotated 8°, body scaled x=1.04/y=0.96

- [ ] **Step 4: Validate and visually compare**

Run: `python3 scripts/validate-mascot-rig.py --root art/mascot-rig`

Expected: only levels 2–7 reported missing; level 1 has no size or alpha errors.

Place `reference-flat.png` and `composite-rest.png` side by side at the same scale. Reject the rig if face landmarks move more than 4px, silhouette differs outside moving joints, or transparent gaps appear in any acceptance composite.

- [ ] **Step 5: Commit the approved prototype**

```bash
git add art/mascot-rig/level-01
git commit -m "art: add level one mascot rig prototype"
```

### Task 3: iOS 파츠 합성과 모션 상태기

**Files:**
- Create: `NaymNaymLevelUp/Resources/MascotRig/level_01/*.png`
- Create: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigModel.swift`
- Create: `NaymNaymLevelUp/Rebuild/Mascot/MascotMotionController.swift`
- Create: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigView.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `NaymNaymLevelUpTests/MascotMotionControllerTests.swift`

**Interfaces:**
- Produces: `MascotMotionController.play(_:)`
- Produces: published `MascotPose`
- Produces: `MascotRigView(level:state:reduceMotion:)`

- [ ] **Step 1: Write failing deterministic pose tests**

```swift
func testMealSuccessUsesSquashThenJumpThenRest() {
    let controller = MascotMotionController(spec: .fixture)
    XCTAssertEqual(controller.pose(for: .mealSuccess, progress: 0.0).bodyScaleY, 1.0)
    XCTAssertEqual(controller.pose(for: .mealSuccess, progress: 0.2).bodyScaleY, 0.96)
    XCTAssertLessThan(controller.pose(for: .mealSuccess, progress: 0.5).bodyOffsetY, 0)
    XCTAssertEqual(controller.pose(for: .mealSuccess, progress: 1.0), .rest)
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/MascotMotionControllerTests"]`.

Expected: FAIL because motion types do not exist.

- [ ] **Step 3: Implement state-to-pose interpolation**

```swift
struct MascotPose: Equatable {
    var bodyOffsetY: CGFloat
    var bodyScaleX: CGFloat
    var bodyScaleY: CGFloat
    var headRotation: Angle
    var leftArmRotation: Angle
    var rightArmRotation: Angle
    var tailRotation: Angle
    var eyesClosed: Bool
    var smiling: Bool
}
```

Render the checksum-verified rest, blink, and soft-skinned pose keyframes with their expression layers in a 1254×1254 `ZStack`; use semantic part assets for state metadata and compositional fallback, not unfeathered rigid transform previews. Use `TimelineView(.animation)` only while a non-rest state is active. For `reduceMotion`, crossfade eyes without offset, scale, rotation, or shine translation.

- [ ] **Step 4: Run tests and profile the prototype**

Run: XcodeBuildMCP `test_sim`.

Expected: PASS.

Run the flagged app, trigger `idle`, `tapReaction`, and `mealSuccess`, and use Xcode animation hitches instrumentation. Acceptance: no hitch longer than one 60Hz frame after initial asset decode.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Resources/MascotRig NaymNaymLevelUp/Rebuild/Mascot NaymNaymLevelUpTests/MascotMotionControllerTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: add iOS mascot rig motion"
```

### Task 4: Android 파츠 합성과 모션 상태기

**Files:**
- Create: `android/app/src/main/res/drawable-nodpi/mascot_l01_*.png`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRigModel.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotMotionController.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRig.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotMotionControllerTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRigTest.kt`

**Interfaces:**
- Produces: `MascotMotionController.pose(state, progress): MascotPose`
- Produces: `@Composable MascotRig(level, state, reduceMotion, modifier)`

- [ ] **Step 1: Write the same pose assertions in Kotlin**

```kotlin
@Test fun mealSuccessUsesSquashThenJumpThenRest() {
    val controller = MascotMotionController(MotionSpec.fixture)
    assertEquals(1f, controller.pose(MotionState.MealSuccess, 0f).bodyScaleY)
    assertEquals(.96f, controller.pose(MotionState.MealSuccess, .2f).bodyScaleY)
    assertTrue(controller.pose(MotionState.MealSuccess, .5f).bodyOffsetY < 0f)
    assertEquals(MascotPose.Rest, controller.pose(MotionState.MealSuccess, 1f))
}
```

- [ ] **Step 2: Run the focused JVM test**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*MascotMotionControllerTest'`

Expected: FAIL because the mascot package does not exist.

- [ ] **Step 3: Implement deterministic Compose transforms**

Use a 1:1 `BoxWithConstraints`, draw checksum-verified pose keyframes and required expression layers with `Image`, and apply only the approved pose interpolation through `graphicsLayer`; semantic part assets support state metadata and compositional fallback, never an unfeathered rigid cutout preview. Load drawable IDs from a level-to-assets map; never use reflection on resource names. `LocalMotionDurationScale` and the app accessibility state must route to `reducedMotion`.

Replace the static `mascot_wave_1` inside `TodayForestScreen.CharacterStage`
with `MascotRig`, mapping the existing `TodayForestUiState.motion` to the
shared motion states. Keep the existing card semantics and accessibility
label so the new renderer is visible in the actual child-home path rather
than only in an isolated prototype.

- [ ] **Step 4: Run unit, Compose, and performance checks**

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: PASS.

Capture a system trace for `mealSuccess` on the reference emulator. Acceptance: no repeated bitmap decode during frames and no frame over 32ms after warm-up.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/drawable-nodpi android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot android/app/src/test android/app/src/androidTest
git commit -m "feat: add Android mascot rig motion"
```

### Task 5: 7단계 성장 자산·정책·도감

**Files:**
- Create: `art/mascot-rig/level-02` … `level-07`
- Create: `NaymNaymLevelUp/Resources/MascotRig/level_02` … `level_07`
- Create: `android/app/src/main/res/drawable-nodpi/mascot_l02_*` … `mascot_l07_*`
- Create: `contracts/native-rebuild/v1/growth-policy.json`
- Create: `NaymNaymLevelUp/Resources/RebuildContracts/growth-policy.json`
- Create: `android/app/src/main/assets/rebuild-contracts/growth-policy.json`
- Modify: `scripts/validate-mascot-rig.py`
- Modify: `scripts/tests/test_validate_mascot_rig.py`
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `scripts/tests/test_native_rebuild_contracts.py`
- Modify: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigModel.swift`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRig.kt`
- Create: `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- Create: `NaymNaymLevelUp/Rebuild/Growth/GrowthView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Growth/CollectionView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Data/RebuildRepositories.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/ChildNavigationView.swift`
- Create: `NaymNaymLevelUpTests/GrowthPolicyTests.swift`
- Create: `NaymNaymLevelUpTests/GrowthRepositoryTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthDomain.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth/CollectionScreen.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDao.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildNavigation.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthPolicyTest.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthRepositoryTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/growth/GrowthScreenTest.kt`

**Interfaces:**
- Produces: `GrowthPolicy.level(totalXP) -> 1...7`
- Produces: one contract-backed title list shared by both platforms, using the current
  `PlayerProgress.levelTitles` values
- Produces: explicit level 1–7 mascot definitions, hashes, and semantic fallback
  maps on both platforms; no reflection, runtime identifier lookup, or level-1 reuse
- Produces: bounded recent positive progress events ordered by
  `occurredAt DESC, id DESC`
- Produces: unlocked-level collection with no grayscale full-character treatment
- Guarantees: every REST composite matches its own immutable
  `Squirrel_Growth_Level_N` source; every level has distinct source/part hashes
- Guarantees: migrated or reconciliation events never receive invented meal copy

- [ ] **Step 1: Add failing policy tests on both platforms**

Use exact thresholds `[0, 80, 180, 320, 500, 720, 1000]` from the current
`PlayerProgress.level`, copied into `growth-policy.json`. Assert every exact
threshold, every `threshold - 1`, negative XP, and the maximum integer on both
platforms. Use the current `PlayerProgress.levelTitles` values as the canonical
seven-title list and remove the conflicting duplicate visual-title policy.

- [ ] **Step 2: Lock, validate, and sync the shared growth contract**

Extend `validate-native-rebuild-contracts.py` and its tests to load and validate
`growth-policy.json`, including increasing thresholds, seven unique levels/titles,
and platform parity. Run:

```bash
python3 scripts/validate-native-rebuild-contracts.py
bash scripts/sync-native-rebuild-contracts.sh
```

Confirm the canonical file is byte-identical to the iOS and Android runtime copies.

- [ ] **Step 3: Produce and validate levels 2–7**

Repeat the accepted level-1 canvas, part names, hidden-area painting, and three acceptance composites for each current `Squirrel_Growth_Level_N` reference.

Extend `validate-mascot-rig.py` and its tests so it cannot accept copied level-1
assets: validate each level's immutable source hash, REST-source identity, unique
part hashes, and REST/BLINK/CELEBRATE composites. Register explicit level 1–7
definitions in both production mascot stores. `mouthNeutral` must be a meaningful
neutral expression, while BLINK preserves the immutable source mouth.

Run: `python3 scripts/validate-mascot-rig.py --root art/mascot-rig`

Expected: `77 parts: PASS`.

- [ ] **Step 4: Implement persisted growth data and real navigation**

Add repository/DAO queries for persisted positive events only (`amount > 0`),
ordered deterministically by `occurredAt DESC, id DESC`, with a bounded limit.
Derive truthful meal identity only from canonical `meal:` event IDs. Legacy UUID
`sourceRecordID` values are not meal identity; render them as generic `+N XP/date`
events, and label `legacy:progress-reconciliation` explicitly.

Replace the real iOS and Android Growth and Collection tab destinations instead
of leaving legacy or placeholder routes. Inject the same Core Data/Room stores
used by meal recording and reload when a tab becomes active. Derive the home
level from persisted total XP through `GrowthPolicy`; do not combine persisted XP
with a stale legacy level.

- [ ] **Step 5: Implement growth policy and screens**

Growth screen order:

1. current rigged character
2. level and XP progress
3. next unlock preview
4. recent positive progress events

Collection uses lit full-color art for unlocked levels and a warm silhouette plus lock label for locked levels. It must not turn the entire original art grayscale.

- [ ] **Step 6: Run both platform suites and visually compare**

Run the focused policy, repository-ordering, navigation, and locked-art tests
first. On iOS, ensure every new Swift/test file is manually registered in the
correct target and source phase; the existing `MascotRig` folder resource
reference must continue to bundle level directories exactly once.

Run: XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: PASS.

Capture level 1, 4, and 7 at the same 390×844-equivalent viewport and compare baseline, anchor, and scale.

- [ ] **Step 7: Commit**

```bash
git add art/mascot-rig contracts/native-rebuild/v1/growth-policy.json \
  scripts/validate-mascot-rig.py scripts/tests/test_validate_mascot_rig.py \
  scripts/validate-native-rebuild-contracts.py scripts/tests/test_native_rebuild_contracts.py \
  NaymNaymLevelUp/Resources/MascotRig NaymNaymLevelUp/Resources/RebuildContracts \
  NaymNaymLevelUp/Rebuild/Mascot/MascotRigModel.swift \
  NaymNaymLevelUp/Rebuild/Growth NaymNaymLevelUp/Rebuild/Data/RebuildRepositories.swift \
  NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift \
  NaymNaymLevelUp/Rebuild/Child/ChildNavigationView.swift \
  NaymNaymLevelUpTests/GrowthPolicyTests.swift \
  NaymNaymLevelUpTests/GrowthRepositoryTests.swift \
  NaymNaymLevelUp.xcodeproj/project.pbxproj \
  android/app/src/main/assets/rebuild-contracts \
  android/app/src/main/res/drawable-nodpi \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/mascot/MascotRig.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/growth \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/data/RebuildDao.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildNavigation.kt \
  android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/growth \
  android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/growth
git commit -m "feat: add seven-stage mascot growth"
```

### Task 6: 인트로 로고와 모션 접근성

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildIntroMotionSpec.swift`
- Create: `NaymNaymLevelUp/Rebuild/Onboarding/RebuildIntroView.swift`
- Modify: `NaymNaymLevelUp/App/RootView.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroMotionSpec.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroScreen.kt`
- Create: `NaymNaymLevelUpTests/RebuildIntroMotionTests.swift`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroMotionTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroScreenTest.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt`
- Create: `docs/qa/native-rebuild-motion-matrix.md`

**Interfaces:**
- Produces: split ratio `0.40`
- Produces: left start `0.04s`, right start `0.34s`, rise duration `0.76s`, shine start `1.18s`, shine duration `0.82s`
- Guarantees: no logo movement after 2.00s
- Produces: `RebuildIntroMotionSpec.frame(at:reduceMotion:) -> RebuildIntroLogoFrame`
- Produces: `RebuildIntroMotionSpec.frameAt(elapsedMs, reduceMotion)`
- Guarantees: the rebuild path retains the existing once-per-local-day intro
  presentation policy instead of adding an unconditional launch splash
- Guarantees: the original 357×86 RGBA logo is rendered directly; no derived
  crop asset, marketing-site logo, overlapping mask, or duplicated stroke

- [ ] **Step 1: Add genuine RED tests for the new frame model**

Do not only retest the already-green legacy constants. Add focused tests against
the missing rebuild frame-model interfaces and assert:

1. the exact timing constants on both platforms
2. left/right opacity, translation, scale, and shine at boundary timestamps
3. frame equality at `2.00s` and every later sampled timestamp
4. Reduce Motion keeps translation, scale delta, and shine at zero while applying
   only a `0.25s` whole-logo fade
5. a second start request cannot restart the sequence
6. cancellation prevents any remaining asynchronous work from mutating state

- [ ] **Step 2: Implement complementary safe-mask logo rendering**

Render the immutable app logo whose SHA-256 is
`0132e9075a8a3953cc87ae43154be317fb846630ea5e1f7dfbced8fb0860120b`.
Its left word ends at source x=138, x=139...145 is fully transparent, and the
right word begins at x=146. Use normalized split `0.40` inside that transparent
gap with complementary, non-overlapping masks. Preserve at least 8px-equivalent
padding around the outer logo viewport, not as mask overlap. Render the original
`357×86` aspect ratio. The shine uses the logo alpha as a mask and runs once.

On Android, combine the system `MotionDurationScale.scaleFactor == 0f` signal
with an explicit test override. Do not depend only on the legacy
`IntroLogoMotionSpec.java`, which is package-private outside the rebuild package.

- [ ] **Step 3: Integrate the real rebuild entry path**

Replace the rebuild branch's missing intro with `RebuildIntroView` /
`RebuildIntroScreen` in the actual iOS `RootView` and Android `RebuildApp`.
Preserve the existing once-per-local-day behavior using persisted local state.
The first rebuild launch, including a new user's onboarding launch, starts with
the intro; subsequent launches that local day proceed directly. iOS deep links
continue to dismiss/mark the daily intro before routing. Do not leave an
unreferenced preview-only screen.

- [ ] **Step 4: Verify clipping and reduced motion**

Inspect 320pt, 393pt, Pro Max, Android 360×800, and a large Android screen at
default and 200% text, both normal and Reduce Motion. Capture:
`0.00, 0.04, 0.34, 0.80, 1.10, 1.18, 2.00, 2.50s`.
Acceptance: `ㅑ` and `ㄹ` have no clipped or duplicated strokes; the 2.00s final
render is pixel-equivalent to the static source logo; Reduce Motion has no
spatial transform or shine.

- [ ] **Step 5: Run complete motion gate**

Run: `python3 scripts/validate-mascot-rig.py --root art/mascot-rig`

Run: XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: all PASS.

- [ ] **Step 6: Update the existing Figma motion frames**

Update existing normal frame `29:2` and Reduce Motion frame `31:2` in place.
Document the complementary left/right mask tracks, timing markers, one-shot shine,
and the 0.25s reduced fade. Do not create duplicate frames.

- [ ] **Step 7: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Onboarding/RebuildIntroMotionSpec.swift \
  NaymNaymLevelUp/Rebuild/Onboarding/RebuildIntroView.swift \
  NaymNaymLevelUp/App/RootView.swift \
  NaymNaymLevelUpTests/RebuildIntroMotionTests.swift \
  NaymNaymLevelUp.xcodeproj/project.pbxproj \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroMotionSpec.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroScreen.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt \
  android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroMotionTest.kt \
  android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/RebuildIntroScreenTest.kt \
  docs/qa/native-rebuild-motion-matrix.md
git commit -m "feat: finish accessible mascot and logo motion"
```

### Task 7: 살아있는 숲 배경 레이어와 절제된 깊이감

**Files:**
- Create: `art/forest-scene/home/source-notes.md`
- Create: `art/forest-scene/home/references/{intro,home}.png`
- Create: `art/forest-scene/home/master-1290x2796.png`
- Create: `art/forest-scene/home/{sky,distantTrees,midgroundTrees,foregroundLeaves,ground}.png`
- Create: `art/forest-scene/home/acceptance-{rest,max-motion}.png`
- Create: `contracts/native-rebuild/v1/forest-scene.json`
- Create: `NaymNaymLevelUp/Resources/RebuildContracts/forest-scene.json`
- Create: `android/app/src/main/assets/rebuild-contracts/forest-scene.json`
- Create: `scripts/validate-forest-scene.py`
- Create: `scripts/tests/test_validate_forest_scene.py`
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `scripts/tests/test_native_rebuild_contracts.py`
- Create: `NaymNaymLevelUp/Resources/ForestScene/Home/*.png`
- Create: `NaymNaymLevelUp/Rebuild/Child/ForestSceneMotion.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/ForestSceneView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigView.swift`
- Create: `NaymNaymLevelUpTests/ForestSceneMotionTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`
- Create: `android/app/src/main/res/drawable-nodpi/forest_home_*.png`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneMotion.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestScene.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneMotionTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneTest.kt`
- Create: `docs/qa/forest-scene-asset-check.md`

**Interfaces:**
- Produces: 1290×2796 portrait master with five aligned layers
- Produces: 860×1864 runtime derivatives for both app bundles
- Produces: `ForestSceneView(reduceMotion:isPaused:content:)`
- Produces: `@Composable ForestScene(reduceMotion, isPaused, content)`
- Produces: contract-backed shared layer order and deterministic 8-second frame model
- Guarantees: text and primary actions remain on high-contrast surfaces, not directly over detailed leaves
- Guarantees: decoded forest layers stay at or below 32 MiB and combined forest
  plus active three-frame mascot art stays at or below 52 MiB
- Guarantees: the release remains iPhone-only; iPad support is not silently added
  as part of this visual task

- [ ] **Step 1: Add genuine RED contract, asset, and motion tests**

Before creating production layers or motion code, add failing tests for:

1. the exact five filenames/order, 1290×2796 master dimensions, RGB/RGBA rules,
   unique hashes, fully opaque sky, and transparent non-sky edges
2. the same cross-platform motion values at `0s`, `2s`, `4s`, `6s`, and `8s`
3. Reduce Motion producing all-zero transforms and no frame callback
4. elapsed time freezing while a sheet, inactive tab, or inactive app pauses the
   scene, then resuming without a jump
5. foreground layers remaining below mascot, text, and primary actions in z-order
6. all user-facing copy sitting on opaque `cream50`-family high-contrast surfaces

- [ ] **Step 2: Establish the immutable visual reference**

Copy the real reference files into `art/forest-scene/home/references` and record
their original paths, dimensions, and SHA-256 values in `source-notes.md`:

- Intro `853×1844`, SHA-256
  `954f62cb4c5989d0acb24e63f731025746d9bac09266a9905def32dabd4dc365`
- Home `1672×941`, SHA-256
  `94566b4593a99918d79c5f2cac1927714474c47afeadb842ade48e66e80d0ee7`

Record approved palette IDs and verified contrast pairs from
`design-tokens.json`. Do not use the duplicate docs copy as a new visual source.

- [ ] **Step 3: Produce five aligned master and runtime layers**

Create an original portrait extension of the approved warm forest world. The sky layer is fully opaque; all other layers are RGBA and retain complete hidden edges for ±12px motion. Do not put characters, text, buttons, icons, or food into the background.

Keep the editable/master layers at `1290×2796` under `art/forest-scene/home`.
Generate deterministic `860×1864` runtime derivatives for iOS and Android; never
decode five full master-size RGBA layers in the app. Add
`forest-scene.json`, the dedicated validator, native contract validation, and
synced runtime copies. Acceptance composites at REST and maximum motion must show
no transparent edge or halo. Runtime forest-layer decoded memory must be
`<=32 MiB`, combined runtime forest plus the active three-frame mascot must be
`<=52 MiB`, and packaged runtime forest PNGs must be recorded in the QA document.

- [ ] **Step 4: Implement matched depth motion**

Use one shared deterministic 8-second cycle, with progress fixed at
`0s=0%`, `2s=50%`, `4s=100%`, `6s=50%`, `8s=0%`:

```text
distantTrees: y -2pt/dp
midgroundTrees: y -4pt/dp
foregroundLeaves: x +6pt/dp, y -3pt/dp
ground: stationary
```

Pause the cycle while the meal recorder sheet is open, the tab is inactive, or
the app is inactive. In Reduce Motion, render all transforms at zero and do not
schedule a display/frame callback. On Android, read the real system motion scale
instead of passing a hard-coded `false`. The character remains the strongest
moving object.

As part of the iOS home composition update, replace the remaining legacy flat
character in `TodayForestView` with the approved `MascotRigView`, mapping the
existing `TodayForestViewModel` motion state, a monotonic `motionRevision` for
consecutive equal success events, and the system Reduce Motion value.

- [ ] **Step 5: Protect content contrast and verify composition/performance**

Place headings, body copy, and primary actions on opaque `cream50`-family
surfaces with contract-token foreground colors. Do not rely on the existing
0.84/0.88 translucent character cards for AA contrast over detailed leaves.

Capture compact iPhone, 390×844, Pro Max, and Android 360×800 at REST, maximum
motion, recorder-sheet pause, Reduce Motion, and 200% text. The app is currently
iPhone-only (`TARGETED_DEVICE_FAMILY=1`); do not add an iPad acceptance capture
unless device support is expanded in a separate approved task.

Confirm the character is never covered, primary-action and copy contrast pass,
no transparent layer edge appears, frame pacing remains inside the release
budget, and the decoded-memory limits hold both from cold home launch and after
visiting Collection then returning home.

- [ ] **Step 6: Save the approved scene system in Figma**

Create one `living-forest-scene` board in the existing Figma file and place the
actual five approved production layers plus REST/maximum-motion frames, z-order,
motion values, pause behavior, contrast surfaces, and memory notes. Reuse that
board for any correction; do not create duplicates.

- [ ] **Step 7: Run the complete cross-platform gate**

Run:

```bash
python3 scripts/validate-forest-scene.py --root art/forest-scene/home
python3 scripts/validate-native-rebuild-contracts.py
bash scripts/sync-native-rebuild-contracts.sh
```

Run XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add art/forest-scene contracts/native-rebuild/v1/forest-scene.json \
  scripts/validate-forest-scene.py scripts/tests/test_validate_forest_scene.py \
  scripts/validate-native-rebuild-contracts.py scripts/tests/test_native_rebuild_contracts.py \
  NaymNaymLevelUp/Resources/ForestScene \
  NaymNaymLevelUp/Resources/RebuildContracts/forest-scene.json \
  NaymNaymLevelUp/Rebuild/Child/ForestSceneMotion.swift \
  NaymNaymLevelUp/Rebuild/Child/ForestSceneView.swift \
  NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift \
  NaymNaymLevelUp/Rebuild/Mascot/MascotRigView.swift \
  NaymNaymLevelUpTests/ForestSceneMotionTests.swift \
  NaymNaymLevelUp.xcodeproj/project.pbxproj \
  android/app/src/main/assets/rebuild-contracts/forest-scene.json \
  android/app/src/main/res/drawable-nodpi/forest_home_*.png \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneMotion.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestScene.kt \
  android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/TodayForestScreen.kt \
  android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneMotionTest.kt \
  android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/child/ForestSceneTest.kt \
  docs/qa/forest-scene-asset-check.md
git commit -m "art: add layered living forest scene"
```
