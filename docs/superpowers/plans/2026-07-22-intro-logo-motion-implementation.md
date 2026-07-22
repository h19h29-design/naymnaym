# Intro Logo Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved one-shot `냠냠 → 레벨업 → 빛` logo motion to the iOS and Android first screens without deploying either app.

**Architecture:** Keep the existing raster logo and render it twice, split at the verified transparent 40% boundary. Store timing and geometry in small testable specs, drive platform-native view animations from those specs, and fall back to a short fade when motion is disabled.

**Tech Stack:** SwiftUI, Swift concurrency, XCTest, Java, Android View animations, JUnit 4, Xcode, Gradle.

## Global Constraints

- Split the 357px source logo at normalized position `0.40`, inside the transparent x=139–145 gap.
- Start `냠냠` at 0.04 seconds and `레벨업` at 0.34 seconds; each rise lasts 0.76 seconds.
- Start the full-logo shine at 1.18 seconds and run it for 0.82 seconds.
- Rise from 10px below and scale from 0.988 to 1.0 with no large bounce.
- Play once and leave the logo at rest after 2.00 seconds.
- When motion is reduced or disabled, use only a 0.25-second full-logo fade.
- Preserve the existing missing-asset placeholder on iOS and the compiled drawable fallback on Android.
- Do not deploy, upload store artifacts, or create a release.
- Stage only files belonging to this feature; preserve all pre-existing worktree changes.

---

### Task 1: iOS Motion Contract and Tests

**Files:**
- Modify: `NaymNaymLevelUp/Views/Onboarding/IntroExperienceView.swift`
- Test: `NaymNaymLevelUpTests/MascotAnimationStateTests.swift`

**Interfaces:**
- Produces: `IntroLogoMotionSpec` timing and geometry constants.
- Produces: `IntroLogoMotionSpec.splitX(for:) -> CGFloat`.
- Consumes: the existing `logo_naym_levelup` asset and `LogoHeader` compact height.

- [x] **Step 1: Write failing iOS motion-contract tests**

```swift
func testIntroLogoSplitFallsInsideVerifiedTransparentGap() {
    let splitX = IntroLogoMotionSpec.splitX(for: 357)
    XCTAssertEqual(splitX, 142.8, accuracy: 0.001)
    XCTAssertGreaterThan(splitX, 138)
    XCTAssertLessThan(splitX, 146)
}

func testIntroLogoMotionUsesApprovedOneShotTiming() {
    XCTAssertEqual(IntroLogoMotionSpec.nyamStart, 0.04, accuracy: 0.001)
    XCTAssertEqual(IntroLogoMotionSpec.levelUpStart, 0.34, accuracy: 0.001)
    XCTAssertEqual(IntroLogoMotionSpec.riseDuration, 0.76, accuracy: 0.001)
    XCTAssertEqual(IntroLogoMotionSpec.shineStart, 1.18, accuracy: 0.001)
    XCTAssertEqual(IntroLogoMotionSpec.shineDuration, 0.82, accuracy: 0.001)
    XCTAssertEqual(IntroLogoMotionSpec.reduceMotionFadeDuration, 0.25, accuracy: 0.001)
}
```

- [x] **Step 2: Run the focused iOS test and verify RED**

Run:

```bash
xcodebuild test \
  -project NaymNaymLevelUp.xcodeproj \
  -scheme NaymNaymLevelUp \
  -destination 'platform=iOS Simulator,name=NaymVerify iPhone 16' \
  -only-testing:NaymNaymLevelUpTests/MascotAnimationStateTests
```

Expected: compile failure because `IntroLogoMotionSpec` does not exist.

- [x] **Step 3: Add the minimal iOS motion contract**

```swift
enum IntroLogoMotionSpec {
    static let sourceAspectRatio: CGFloat = 357.0 / 86.0
    static let splitFraction: CGFloat = 0.40
    static let initialYOffset: CGFloat = 10
    static let initialScale: CGFloat = 0.988
    static let nyamStart: TimeInterval = 0.04
    static let levelUpStart: TimeInterval = 0.34
    static let riseDuration: TimeInterval = 0.76
    static let shineStart: TimeInterval = 1.18
    static let shineDuration: TimeInterval = 0.82
    static let reduceMotionFadeDuration: TimeInterval = 0.25

    static func splitX(for width: CGFloat) -> CGFloat {
        width * splitFraction
    }
}
```

- [x] **Step 4: Run the focused test and verify GREEN**

Expected: all `MascotAnimationStateTests` pass.

---

### Task 2: iOS One-Shot Logo View

**Files:**
- Modify: `NaymNaymLevelUp/Views/Onboarding/IntroExperienceView.swift`
- Test: `NaymNaymLevelUpTests/MascotAnimationStateTests.swift`

**Interfaces:**
- Consumes: `IntroLogoMotionSpec`.
- Produces: private `AnimatedIntroLogo` used by `LogoHeader`.

- [x] **Step 1: Replace the static logo with an aspect-locked animation container**

Use an explicit width of `height * IntroLogoMotionSpec.sourceAspectRatio` so the 40% mask is measured against the image rather than the full screen. Draw two identical images:

```swift
Image("logo_naym_levelup")
    .resizable()
    .scaledToFit()
    .frame(width: logoWidth, height: height)
    .mask(alignment: .leading) {
        Rectangle().frame(width: IntroLogoMotionSpec.splitX(for: logoWidth))
    }
```

Use the complementary trailing mask for `레벨업`. Apply opacity, 10px Y offset, and 0.988 scale independently.

- [x] **Step 2: Sequence the two rises and masked shine**

In one cancellable `.task`, reset state, wait until 0.04 seconds, animate `냠냠`, wait 0.30 seconds, animate `레벨업`, then wait 0.84 seconds and move a bright gradient across a full-logo image mask for 0.82 seconds. Use `Animation.timingCurve(0.22, 0.78, 0.36, 1, duration: 0.76)` for each rise. Do not repeat.

- [x] **Step 3: Add the Reduce Motion path**

When `accessibilityReduceMotion` is true, render one full logo image, fade it from 0 to 1 in 0.25 seconds, and skip masks, offsets, scaling, and shine.

- [x] **Step 4: Run focused tests and build iOS**

Run the focused test command from Task 1, then:

```bash
xcodebuild build \
  -project NaymNaymLevelUp.xcodeproj \
  -scheme NaymNaymLevelUp \
  -destination 'platform=iOS Simulator,name=NaymVerify iPhone 16'
```

Expected: test and build both succeed.

- [x] **Step 5: Commit the iOS implementation**

```bash
git add NaymNaymLevelUp/Views/Onboarding/IntroExperienceView.swift \
        NaymNaymLevelUpTests/MascotAnimationStateTests.swift
git commit -m "feat: animate intro logo on iOS"
```

---

### Task 3: Android Motion Contract and Tests

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpec.java`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpecTest.java`

**Interfaces:**
- Produces: Android timing constants matching iOS.
- Produces: `IntroLogoMotionSpec.contentLeft(...)`, `contentWidth(...)`, and `splitX(...)` for a FIT_CENTER drawable.

- [x] **Step 1: Write failing Android split and timing tests**

```java
@Test public void splitFallsInsideSourceTransparentGap() {
    assertEquals(143, IntroLogoMotionSpec.splitX(357, 86, 357, 86));
}

@Test public void splitUsesActualFitCenterContentBounds() {
    assertEquals(149, IntroLogoMotionSpec.splitX(360, 74, 357, 86));
}

@Test public void timingMatchesApprovedSequence() {
    assertEquals(40L, IntroLogoMotionSpec.NYAM_START_MS);
    assertEquals(340L, IntroLogoMotionSpec.LEVEL_UP_START_MS);
    assertEquals(760L, IntroLogoMotionSpec.RISE_DURATION_MS);
    assertEquals(1180L, IntroLogoMotionSpec.SHINE_START_MS);
    assertEquals(820L, IntroLogoMotionSpec.SHINE_DURATION_MS);
}
```

- [x] **Step 2: Run Android unit tests and verify RED**

Run:

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

Expected: test compilation fails because `IntroLogoMotionSpec` does not exist.

- [x] **Step 3: Implement the pure Android motion contract**

Compute FIT_CENTER scale with `min(viewWidth / drawableWidth, viewHeight / drawableHeight)`, round the displayed width, center it horizontally, and add 40% of that displayed width to the left edge. Keep this class free of `Activity` and `View` dependencies.

- [x] **Step 4: Run Android unit tests and verify GREEN**

Expected: all Android JVM tests pass.

---

### Task 4: Android One-Shot Logo View

**Files:**
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java`
- Consume: `android/app/src/main/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpec.java`
- Test: `android/app/src/test/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpecTest.java`

**Interfaces:**
- Consumes: `IntroLogoMotionSpec`.
- Produces: private `createAnimatedIntroLogo()` returning a `FrameLayout`.

- [x] **Step 1: Replace the single logo ImageView with layered logo views**

Create a 74dp-high `FrameLayout`. Add `냠냠`, `레벨업`, reduced-motion full-logo `ImageView` layers using `FIT_CENTER`, plus a masked shine view. After layout, compute the actual split with `IntroLogoMotionSpec.splitX(...)` and assign complementary `clipBounds` with no overlap.

- [x] **Step 2: Animate the word groups**

Initialize both word layers at alpha 0, translationY 10dp, and scale 0.988. Use `ViewPropertyAnimator` with a `PathInterpolator(0.22f, 0.78f, 0.36f, 1f)`, the approved delays, and 760ms duration.

- [x] **Step 3: Animate the shine and accessibility fallback**

Draw a white-to-gold gradient through the logo alpha mask and move it across the actual drawable content with a `ValueAnimator` starting at 1180ms. Fade the band at both ends. If system animators are disabled, show a single full logo fade for 250ms and do not run translation, scale, or shine. Expose one `냠냠레벨업` accessibility label on the container and hide duplicate child labels.

- [x] **Step 4: Run Android tests and build**

```bash
cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

Expected: all tasks succeed. Do not run Play upload, bundle publishing, or deployment tasks.

- [x] **Step 5: Commit the Android implementation**

```bash
git add android/app/src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java \
        android/app/src/main/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpec.java \
        android/app/src/test/java/com/h19h29/naymnaymlevelup/IntroLogoMotionSpecTest.java
git commit -m "feat: animate intro logo on Android"
```

---

### Task 5: Cross-Platform Verification and Push

**Files:**
- Update: `docs/superpowers/plans/2026-07-22-intro-logo-motion-implementation.md`

**Interfaces:**
- Produces: passing iOS and Android test/build evidence.
- Produces: pushed current branch without deployment.

- [x] **Step 1: Run final focused and repository checks**

Run the iOS focused test and simulator build from Tasks 1–2, then:

```bash
cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
cd ..
git diff --check
git status --short
```

Expected: all tests/builds pass, no whitespace errors, and pre-existing unrelated modifications remain unstaged.

- [x] **Step 2: Mark completed plan checkboxes and commit the plan**

```bash
git add docs/superpowers/plans/2026-07-22-intro-logo-motion-implementation.md
git commit -m "test: verify intro logo motion"
```

- [x] **Step 3: Push the current branch only**

```bash
git push origin codex/fix-student-growth-p1
```

Expected: remote branch advances. Do not deploy or upload any build artifact.
