# Growth & Meal Polish v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 출시된 iOS 앱 `급식레벨업`의 Rebuild 경험을 12단계 성장, 정확한 날짜별 급식 상세, 메뉴별 영양 학습, 알레르기 안전, 음식 시각화와 접근성까지 업데이트하되 공개 1.1 사용자의 XP·기록·사진·배지·스킨·보호자 연결을 보존한다.

**Architecture:** 기존 `Rebuild` SwiftUI 화면·정책 로더·Core Data v1·`LegacyDefaultsReader`·`RecordMealUseCase`·`NutritionRuleEngine`을 확장한다. 성장 권리는 기존 XP 원장과 read-only legacy 권리의 union을 계산하고 bounded `growth-stage-state-v2` UserDefaults에만 캐시한다. 영양 안내는 기존 Core Data 모델을 바꾸지 않고 정확한 meal-record revision에 결합한 Application Support immutable sidecar로 보존한다. 주간·월간은 `MealDayRoute`로 같은 `MealDayDetailView`를 연다.

**Tech Stack:** SwiftUI, XCTest, Core Data programmatic model (iOS 16+), Foundation/UserDefaults, CryptoKit, 기존 Lottie fallback·MascotRig·NEIS/Rebuild 저장소, 기존 JSON 계약과 shell/Python 검증 스크립트. 새 애니메이션 엔진·네트워크 계층·외부 패키지는 추가하지 않는다.

**Spec:** [`docs/superpowers/specs/2026-08-30-growth-meal-polish-v2-design.md`](../specs/2026-08-30-growth-meal-polish-v2-design.md)

## Global Constraints

- 성장 정책·화면·접근성 라벨·테스트의 단계 수는 정확히 12개다. 공개 1–7의 이름과 시작 XP는 유지하고, XP 원장이나 과거 기록을 재작성·감소·강등하지 않는다.

  | 단계 | 시작 XP | 이름 |
  |---:|---:|---|
  | 1 | 0 | 냠냠 새싹 |
  | 2 | 80 | 한 입 탐험가 |
  | 3 | 180 | 냠냠 용사 |
  | 4 | 320 | 편식 몬스터 사냥꾼 |
  | 5 | 500 | 급식 히어로 |
  | 6 | 720 | 영양 마스터 |
  | 7 | 1000 | 레전드 냠냠러 |
  | 8 | 1300 | 별빛 셰프 |
  | 9 | 1650 | 균형 수호자 |
  | 10 | 2050 | 숲의 영양 기사 |
  | 11 | 2500 | 황금 한입 챔피언 |
  | 12 | 3000 | 전설의 급식대장 |

- Core Data v1 프로그램식 모델, `NaymRebuild.sqlite`, 모든 기존 entity/attribute/optional/unique constraint, `RebuildMigrationState` version/digest와 공개 v1 migration 경로를 변경하지 않는다. 새 Core Data column/entity/model version, v2 migration 또는 v2 backfill을 만들지 않는다.
- `growth-stage-state-v2`는 `version`, `highestUnlockedStageID`, `selectedStageID`만 갖는 bounded Codable cache다. `highestUnlockedStageID`는 XP 단계·유효 legacy level·유효 `skin-1...skin-7` 단계·기존 cache의 최대를 1...12로 clamp하고 낮아지지 않게 저장한다. raw `player-progress` bytes는 read-only로 읽고 재인코딩·삭제하지 않는다. legacy badge와 skin 권리는 union하되 새 도감 분모와 섞지 않는다.
- 영양 snapshot은 `NutrientImpactSnapshot` version 1 immutable JSON sidecar로만 저장한다. `recordID + date + normalizedMenuName + status + recordUpdatedAt`의 안전한 fingerprint와 정확히 일치하는 active record revision에서만 읽는다. sidecar에는 메뉴·학교·프로필·부모 연결 복제, 개별 메뉴 g/mg/kcal, 의료 진단·결핍 단정, 알레르기 회피를 번복하는 문구를 넣지 않는다.
- 기록 순서는 안전한 command/snapshot 동결 → sidecar 임시 파일·원자 rename·read-back 및 금지 문구 검증 → 기존 Core Data record/event transaction → 동일 fingerprint read-back이다. Core Data 저장 실패 시 sidecar가 orphan이어도 active record와 결합되지 않으며 기존 matching snapshot을 덮어쓰지 않는다.
- `RebuildEatingStatus`의 기존 raw 값 6개를 유지한다. UI에서는 `finished`(다 먹었어요), `half`(반 정도 먹었어요), `oneBite`(한 입 도전), `smelledOnly`(냄새만 맡았어요), `difficultToday`(오늘은 안 먹어요), `allergyAvoided`(알레르기로 피했어요)로 명확히 표시한다. 알레르기 코드가 겹치면 `allergyAvoided`만 저장 가능하고 나머지는 UI·use case 양쪽에서 차단한다.
- 메뉴별 정량 영양값을 추정하지 않는다. 구조화된 `RebuildMealItem.nutrients`와 기존 `NutritionRuleEngine`을 우선하고, otherwise exact/keyword/fallback confidence와 대표 영양소 교육 문장만 보여준다. NEIS 전체 급식 총량에는 전체 급식 출처 라벨을 붙인다.
- 기존 `RebuildMealRepository`, `MealLoadState`, `RebuildMealDay`, `RebuildMealItem`, `GrowthPolicy`, `MascotRig`, `RebuildDesignTokens`를 재사용한다. `GrowthSystem`, `MealPlatform`, `NutritionService` 같은 중복 계층이나 새 의존성은 만들지 않는다.
- Ponytail 점검은 각 task의 새 파일을 만들기 전에 `rg`로 기존 helper/protocol/view를 검색하는 것이다. 새 파일은 공통 날짜 상세·메뉴 표현·sidecar처럼 기존 책임에 넣으면 과밀해지는 경우와 해당 테스트/manifest로 제한하고, 이미 있는 저장소·정책·애니메이션·컴포넌트를 복제하지 않는다.
- 에셋은 기존 `Squirrel_Growth_Level_1...7`, `Resources/MascotRig/level_01...07`, forest layer와 first-party/Lottie 자산을 우선한다. 8–12의 검증된 원화가 없으면 단계명·XP를 유지하는 중립 fallback을 사용하며, SF Symbols 번호 덧씌우기·출처 불명 PNG·라이선스 불명 아이콘은 최종 자산으로 사용하지 않는다. 새 자산은 manifest와 `THIRD_PARTY_NOTICES.md` 없이는 번들에 넣지 않는다.
- 모든 주요 동작은 48×48pt 이상, system-scalable Dynamic Type, VoiceOver 순서(날짜 → 상태 → 메뉴 → 알레르기 → 영양 → 기록 CTA), Reduce Motion 정적 fallback, Increase Contrast를 지킨다. 색만으로 잠금·완료·알레르기를 구분하지 않는다.
- 실제 학교 API 실패·API 키 없음·급식 없음은 샘플 데이터로 대체하지 않는다. 캐시·갱신·live·empty·failed 상태를 보존한다. 로그에 프로필 이름, 학교 상세, 메뉴 전문, 보호자 링크, secret을 남기지 않는다.
- 현재 baseline에는 `Codex Clean iPhone 17 Pro`만 존재한다(UDID `5D3D62C5-12A4-49A3-8D44-F513FCEAFDED`). QA 단계에서 설치된 runtime/device type에 iPhone 16과 SE-class가 있으면 호환 simulator를 생성·부팅하고, 없으면 생성 불가 사유와 실제 수행한 17 Pro QA를 보고서에 투명하게 남긴다. 존재하지 않는 기기에서 통과했다고 주장하지 않는다.
- 이번 작업의 외부 범위는 로컬 build, simulator/실기기 QA, 스크린샷·metadata/docs, Git commit/push까지다. App Store Connect/실제 App Store 업로드·심사 제출·TestFlight 배포 버튼은 누르지 않는다. Apple/GitHub 인증·2FA·유료 자산·법적 동의가 필요하면 그 지점에서 중단하고 정확히 보고한다.

---

### Task 1: Lock the twelve-stage contract before feature code

**Files:**
- Modify: `contracts/native-rebuild/v1/growth-policy.json`
- Modify: `NaymNaymLevelUp/Resources/RebuildContracts/growth-policy.json`
- Modify: `android/app/src/main/assets/rebuild-contracts/growth-policy.json` (canonical mirror only; no Android feature work)
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `scripts/tests/test_native_rebuild_contracts.py`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- Modify: `NaymNaymLevelUpTests/GrowthPolicyTests.swift`

**Interfaces:**
- `GrowthPolicy.init(data:)` accepts only the version-1 document with exactly 12 strictly increasing thresholds and 12 unique non-empty titles.
- `GrowthPolicy.level(totalXP:)`, `title(for:)`, `nextThreshold(totalXP:)`, and `progress(totalXP:)` keep their existing public signatures and return stage 12 for all XP ≥ 3000.
- The Python validator and all mirrored JSON files assert the same 12 thresholds/titles; `PlayerProgress.levelThresholds` remains the legacy 1–7 contract.

- [ ] Step 1: Change `GrowthPolicyTests.testEveryLevelBoundaryMatchesSharedContract` and `testDocumentKeepsExactThresholdsAndTitles` to exercise the exact table above, including 2999 → 11, 3000 → 12, 4850 → 12, and `Int.max` → 12. Add `testPolicyRejectsAnyStageCountOtherThanTwelve` with a seven- and thirteen-stage document, and update Python `test_growth_policy_preserves_shipped_thresholds_and_titles` plus `test_validator_rejects_growth_policy_stage_count_drift` to assert the same 12-stage contract.

  ```swift
  func testCanonicalPolicyHasExactlyTwelveStages() throws {
      XCTAssertEqual(try policy.thresholds, [0, 80, 180, 320, 500, 720, 1_000, 1_300, 1_650, 2_050, 2_500, 3_000])
      XCTAssertEqual(try policy.level(totalXP: 3_000), 12)
      XCTAssertEqual(try policy.level(totalXP: 4_850), 12)
  }
  ```

- [ ] Step 2: Run the focused RED command and confirm the current 14-stage fixture fails on count, thresholds, titles, and upper boundary rather than silently accepting the old policy.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/GrowthPolicyTests
  ```

  Expected RED: `GrowthPolicyTests` reports the old 14-stage expectations and `GrowthPolicy.init(data:)` still accepts a 14-stage document.

- [ ] Step 3: Update only the policy count guard and canonical JSON/validator expectations. Keep version 1, legacy first seven values, XP arithmetic, and `PlayerProgress` source unchanged. Run `bash scripts/sync-native-rebuild-contracts.sh` so the canonical contract and iOS/Android mirrors have identical bytes.
- [ ] Step 4: Run the GREEN commands and confirm Swift boundaries, Python validator, sync checksum, and existing contract tests pass.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/GrowthPolicyTests
  python3 -m unittest discover -s scripts/tests -p 'test_native_rebuild_contracts.py'
  bash scripts/sync-native-rebuild-contracts.sh
  ```

- [ ] Step 5: Commit the contract-only change.

  ```bash
  git add contracts/native-rebuild/v1/growth-policy.json NaymNaymLevelUp/Resources/RebuildContracts/growth-policy.json android/app/src/main/assets/rebuild-contracts/growth-policy.json scripts/validate-native-rebuild-contracts.py scripts/tests/test_native_rebuild_contracts.py NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift NaymNaymLevelUpTests/GrowthPolicyTests.swift
  git commit -m "test: lock twelve-stage growth contract"
  ```

### Task 2: Preserve legacy rights and expose bounded growth state

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`
- Modify: `NaymNaymLevelUp/Stores/LocalStores.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Migration/LegacyDefaultsReader.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Migration/RebuildMigrationCoordinator.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/CollectionView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/CollectionProgress.swift`
- Modify: `NaymNaymLevelUpTests/GrowthPolicyTests.swift`
- Modify: `NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests.swift`
- Modify: `NaymNaymLevelUpTests/CollectionProgressTests.swift`
- Modify: `NaymNaymLevelUpTests/RebuildPersistentStoreTests.swift` (assertions only; no model change)

**Interfaces:**
- Add to the existing growth/store files, not a new feature layer:

  ```swift
  struct GrowthStageStateV2: Codable, Equatable, Sendable {
      static let key = "growth-stage-state-v2"
      let version: Int
      let highestUnlockedStageID: Int
      let selectedStageID: Int?
  }

  struct LegacyGrowthRights: Equatable, Sendable {
      let level: Int?
      let currentSkinID: String?
      let badges: [String]
  }

  struct GrowthEntitlement: Equatable, Sendable {
      let highestUnlockedStageID: Int
      let selectedStageID: Int
      let legacyBadgeIDs: [String]
  }

  protocol GrowthStageStateStore: Sendable {
      func read() -> GrowthStageStateV2?
      func writeMonotonic(_ state: GrowthStageStateV2)
  }

  struct UserDefaultsGrowthStageStateStore: GrowthStageStateStore {
      init(defaults: UserDefaults)
      func read() -> GrowthStageStateV2?
      func writeMonotonic(_ state: GrowthStageStateV2)
  }

  enum GrowthEntitlementResolver {
      static func resolve(policy: GrowthPolicy, totalXP: Int, legacy: LegacyGrowthRights, stored: GrowthStageStateV2?) -> GrowthEntitlement
  }
  ```

- `UserDefaultsGrowthStageStateStore` reads/writes only the three bounded v2 fields, clamps 1...12, and never lowers an existing highest stage. `LegacyDefaultsReader` supplies `LegacyGrowthRights` from raw payload without mutating the payload. `GrowthView`/`CollectionView` use the resolver; `CollectionProgress` keeps legacy badges outside the new badge denominator.

- [ ] Step 1: Add failing tests named `testHighestUnlockedIsMonotonicUnionOfXPLegacyLevelSkinAndStoredState`, `testMalformedAndPartialV2PayloadCannotLowerLegacyRights`, `testLegacyProgressBytesAndV1MigrationStateRemainUnchanged`, `testLegacyBadgeAndSkinRightsAreVisibleWithoutChangingLegacyPayload`, `testCompletedV1MigrationRemainsAlreadyCompleted`, and `testMissingStageAssetUsesVerifiedOneToSevenFallback`. Assert that a legacy level 7/skin-7 user with malformed v2 state never becomes stage 1, original raw `player-progress` bytes are byte-for-byte equal, and Core Data model attributes/optionals/unique constraints remain the existing exact set.

  ```swift
  func testMalformedAndPartialV2PayloadCannotLowerLegacyRights() throws {
      let defaults = UserDefaults(suiteName: #function)!
      defaults.set(Data(#"{"version":1,"highestUnlockedStageID":2}"#.utf8), forKey: GrowthStageStateV2.key)
      let result = GrowthEntitlementResolver.resolve(
          policy: try policy,
          totalXP: 1_000,
          legacy: LegacyGrowthRights(level: 7, currentSkinID: "skin-7", badges: ["legacy-badge"]),
          stored: UserDefaultsGrowthStageStateStore(defaults: defaults).read()
      )
      XCTAssertEqual(result.highestUnlockedStageID, 7)
      XCTAssertEqual(result.selectedStageID, 7)
  }
  ```

- [ ] Step 2: Run the focused RED command. Expected RED: the new resolver/store symbols do not exist and the existing migration test still assumes no bounded growth state.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/GrowthPolicyTests -only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests -only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests -only-testing:NaymNaymLevelUpTests/CollectionProgressTests
  ```

- [ ] Step 3: Implement the resolver using the spec’s exact union: `xpStage`, valid raw legacy level, valid `skin-1...skin-7` suffix, and valid stored highest, clamped to 1...12; select stored unlocked stage, then legacy skin, then highest. Persist only a higher bounded v2 value. Keep v1 migration coordinator version/digest and all existing migration writes unchanged. Feed 12 policy entries to the growth roadmap and collection 2-column grid; clamp only the visual MascotRig art lookup to the highest verified 1–7 body and label stages 8–12 as neutral fallback when no asset is present.
- [ ] Step 4: Run GREEN and verify growth UI has no hard-coded 14, legacy badges remain visible as a separate group, XP/record/photo/link counts and Core Data exact schema tests pass, and a malformed v2 cache is ignored without deleting or rewriting legacy defaults.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/GrowthPolicyTests -only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests -only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests -only-testing:NaymNaymLevelUpTests/CollectionProgressTests
  rg -n "14|14단계|캐릭터 14" NaymNaymLevelUp/Rebuild NaymNaymLevelUpTests || true
  ```

- [ ] Step 5: Commit the rights-preservation change.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Growth NaymNaymLevelUp/Stores/LocalStores.swift NaymNaymLevelUp/Rebuild/Migration/LegacyDefaultsReader.swift NaymNaymLevelUp/Rebuild/Migration/RebuildMigrationCoordinator.swift NaymNaymLevelUpTests/GrowthPolicyTests.swift NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests.swift NaymNaymLevelUpTests/CollectionProgressTests.swift NaymNaymLevelUpTests/RebuildPersistentStoreTests.swift
  git commit -m "feat: preserve growth rights across twelve stages"
  ```

### Task 3: Make calendar periods and date routes exact

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new Swift source)
- Modify: `NaymNaymLevelUpTests/RebuildMealRepositoryTests.swift`
- Create: `NaymNaymLevelUpTests/MealScheduleSelectionTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new test source)

**Interfaces:**
- Add the smallest route/value types beside the existing meal domain:

  ```swift
  struct MealDayRoute: Hashable, Identifiable, Sendable {
      let dateKey: String
      var id: String { dateKey }
  }

  @MainActor
  final class MealDayDetailViewModel: ObservableObject {
      init(route: MealDayRoute, repository: any MealScheduleRepository, school: RebuildSchool?)
      func load() async
      var meal: RebuildMealDay? { get }
      var state: MealLoadState { get }
  }

  enum MealScheduleCalendar {
      static func weekDates(containing date: Date) -> [Date] // exactly Monday...Sunday
      static func monthGridDates(containing date: Date) -> [Date] // complete Monday...Sunday rows, weekends retained
  }
  ```

- `MealScheduleViewModel` continues to own `[String: RebuildMealDay]` and `MealLoadState` semantics. `MealDayDetailViewModel` takes a `MealDayRoute` and repository, requests only that `dateKey`, and exposes cached/refreshing/live/empty/failed without replacing a missing selected day with today or the first loaded meal.

- [ ] Step 1: Add `MealScheduleSelectionTests` cases `testWeekContainsMondayThroughSundaySevenDays`, `testMonthGridIncludesWeekendAndCompleteRows`, `testSeoulMidnightProducesTheLocalDateKey`, `testSelectedDateRequestsTheSameDateKey`, `testMissingSelectedDateDoesNotUseTodayFallback`, and `testFailedSelectedDateRetainsItsOwnCachedState`. Use a recording repository spy to assert the exact requested key.

  ```swift
  func testSelectedDateRequestsTheSameDateKey() async {
      let repository = RecordingMealScheduleRepository(states: ["2026-08-12": .empty])
      let viewModel = MealDayDetailViewModel(route: MealDayRoute(dateKey: "2026-08-12"), repository: repository, school: nil)
      await viewModel.load()
      XCTAssertEqual(await repository.requestedDates, ["2026-08-12"])
      XCTAssertNil(viewModel.meal)
  }
  ```

- [ ] Step 2: Run RED. Expected RED: `weekDates` currently returns five dates, monthly data filters weekends, and the shared route/detail types do not exist.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealScheduleSelectionTests -only-testing:NaymNaymLevelUpTests/RebuildMealRepositoryTests
  ```

- [ ] Step 3: Change the calendar to Asia/Seoul Gregorian Monday-first seven-day weeks and complete seven-column month rows. Use date components/noon-safe arithmetic. Add `MealDayRoute` navigation and the shared `MealDayDetailView`; pass only the route, not a stale meal snapshot. Wire Today, weekly cells, and monthly cells to the same route and preserve `MealLoadState` badges/actions.
- [ ] Step 4: Run GREEN and verify weekly/monthly cells show a compact menu preview before selection, tapping any date opens that exact date detail, weekends remain present, and empty/error selected dates do not display another date’s meal.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealScheduleSelectionTests -only-testing:NaymNaymLevelUpTests/RebuildMealRepositoryTests
  ```

- [ ] Step 5: Commit the calendar/detail routing change.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift NaymNaymLevelUpTests/RebuildMealRepositoryTests.swift NaymNaymLevelUpTests/MealScheduleSelectionTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
  git commit -m "feat: connect meal calendar dates to shared detail"
  ```

### Task 4: Add safe menu visuals and representative nutrition feedback

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`
- Create: `NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new Swift source)
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift`
- Modify: `contracts/native-rebuild/v1/nutrition-rules.json`
- Modify: `NaymNaymLevelUp/Resources/RebuildContracts/nutrition-rules.json`
- Modify: `android/app/src/main/assets/rebuild-contracts/nutrition-rules.json` (canonical mirror only)
- Modify: `scripts/validate-native-rebuild-contracts.py`
- Modify: `scripts/tests/test_native_rebuild_contracts.py`
- Create: `NaymNaymLevelUpTests/MealPresentationTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new test source)

**Interfaces:**
- `MealPresentation.swift` contains one pure resolver rather than a new service:

  ```swift
  enum NutritionMatchConfidence: String, Codable, Sendable {
      case exact, keyword, fallback
  }

  enum MealFoodCategory: String, Codable, CaseIterable, Sendable {
      case grain, soup, meat, fish, egg, bean, vegetable, fruit, dairy, noodle, bread, kimchi, other
  }

  struct MealVisual: Equatable, Sendable {
      let category: MealFoodCategory
      let iconKey: String
      let confidence: NutritionMatchConfidence
      let representativeNutrientIDs: [String]
  }

  enum MealVisualResolver {
      static func resolve(item: RebuildMealItem, engine: NutritionRuleEngine) -> MealVisual
  }
  ```

- Extend existing `NutritionInsight`/rules with optional `foodCategory`, `confidence`, `iconKey`, and `representativeNutrientIDs`; absent fields decode to safe defaults. `structured nutrients > exact > keyword > fallback` is deterministic. Fallback uses a bundled safe symbol key, never a missing image lookup.

- [ ] Step 1: Add tests `MealPresentationTests.testStructuredNutrientsWinOverKeywordRules`, `testExactKeywordAndFallbackConfidenceAreDeterministic`, `testEveryFoodCategoryHasAnIconManifestKey`, `testUnknownMenuUsesNeutralFallbackWithoutLoadingMissingAsset`, `testRepresentativeCopyContainsNoQuantities`, and `testWholeMealTotalsCarryTheWholeMealSourceLabel`. Update Python `test_validator_accepts_optional_nutrition_presentation_fields` and `test_validator_rejects_unknown_nutrition_icon_key`; assert the snapshot/copy never contains regex matches for `\\d+\\s*(g|mg|kcal)` or medical-deficiency wording.

  ```swift
  func testUnknownMenuUsesNeutralFallbackWithoutLoadingMissingAsset() throws {
      let item = RebuildMealItem(name: "처음 보는 메뉴", allergyCodes: [], nutrients: [], tags: [], sourceRawText: "처음 보는 메뉴")
      let visual = MealVisualResolver.resolve(item: item, engine: try NutritionRuleEngine(ruleData: canonicalRules))
      XCTAssertEqual(visual.confidence, .fallback)
      XCTAssertEqual(visual.iconKey, "food.other")
      XCTAssertFalse(visual.iconKey.isEmpty)
  }
  ```

- [ ] Step 2: Run RED. Expected RED: `MealVisualResolver` and confidence/category fields are absent, and current nutrition contract validator rejects the optional schema.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealPresentationTests
  python3 -m unittest discover -s scripts/tests -p 'test_native_rebuild_contracts.py'
  ```

- [ ] Step 3: Extend the existing rule decoder/contract validator with optional fields, retain existing rule order/version and child-safe copy, and implement the pure resolver. Add 12–24 manifest-backed icon keys; use existing licensed asset names where present and SF Symbols only as an explicit `food.other`/category fallback. Render icon, original menu name, allergy marker, representative nutrient chips, and whole-meal totals in the schedule/detail/recording views.
- [ ] Step 4: Run GREEN and check the Python mirrors, structured-over-keyword precedence, exact/fallback labels, and absence of per-menu quantities or unsafe copy.

  ```bash
  python3 -m unittest discover -s scripts/tests -p 'test_native_rebuild_contracts.py'
  bash scripts/sync-native-rebuild-contracts.sh
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealPresentationTests
  ```

- [ ] Step 5: Commit the menu visual/rule change.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift contracts/native-rebuild/v1/nutrition-rules.json NaymNaymLevelUp/Resources/RebuildContracts/nutrition-rules.json android/app/src/main/assets/rebuild-contracts/nutrition-rules.json scripts/validate-native-rebuild-contracts.py scripts/tests/test_native_rebuild_contracts.py NaymNaymLevelUpTests/MealPresentationTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
  git commit -m "feat: add safe menu visuals and nutrition feedback"
  ```

### Task 5: Implement the immutable nutrition sidecar and exact meal revision

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Meal/NutrientImpactSidecar.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new Swift source)
- Create: `NaymNaymLevelUpTests/NutrientImpactSidecarTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add the new test source)
- Modify: `NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift`

**Interfaces:**
- Implement the spec’s exact value/protocol surface:

  ```swift
  struct NutrientImpactSnapshot: Codable, Hashable, Sendable {
      let schemaVersion: Int
      let ruleVersion: Int
      let recordID: String
      let date: String
      let normalizedMenuName: String
      let status: RebuildEatingStatus
      let recordUpdatedAt: Date
      let nutrients: [String]
      let headline: String
      let explanation: String
      let alternatives: [String]
      let disclaimer: String
  }

  protocol NutrientImpactSidecar: Sendable {
      func install(_ snapshot: NutrientImpactSnapshot) throws
      func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot?
  }

  struct FileNutrientImpactSidecar: NutrientImpactSidecar {
      init(directoryURL: URL, fileManager: FileManager = .default)
      func install(_ snapshot: NutrientImpactSnapshot) throws
      func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot?
  }

  struct RebuildMealRecordRevision: Equatable, Sendable {
      let recordID: String
      let date: String
      let normalizedMenuName: String
      let status: RebuildEatingStatus
      let updatedAt: Date
  }
  ```

- `FileNutrientImpactSidecar` stores under an Application Support subdirectory, hashes a canonical revision string with existing CryptoKit, accepts only `NutrientImpactCopyCatalog` canonical copy for each status and normalized nutrient-ID list, writes temp → atomic rename → read-back, never overwrites a prior revision, and returns nil for malformed/schema/rule/fingerprint mismatch. `SameMealAlternativeSelector` accepts only an actual member of one `RebuildMealDay`; it derives canonical target IDs from real structured Korean/English nutrients or a non-fallback visual rule through the shared nutrient canonicalizer. Its typed selection carries date, shared trim+lowercase menu identity, and target nutrient provenance even when no candidate qualifies. The selector excludes current/allergy-overlapping items and deterministically prioritizes shared nutrient coverage before original menu order, capped at two unique labels. `NutrientImpactSnapshotFactory` accepts that typed selection (never raw alternative strings), checks date/menu/nutrient provenance for empty and non-empty results alike, supplies canonical copy, and exposes a separate safe no-alternative overload. Include a no-op implementation for callers that record without an impact snapshot.

- [ ] Step 1: Add failing tests `testInstallRoundTripsOnlyForExactRevision`, `testStatusChangeCreatesNewImmutableFile`, `testCorruptedOrMismatchedSnapshotFallsBackToCurrentGuidance`, `testSidecarRejectsOnlyNonCanonicalStructuralLabels`, and `testSidecarDoesNotChangeManagedModelSchema`. Also lock the six canonical copy rows, typed same-day alternative provenance/priority, allergy/no-alternative branching, selection mismatch rejection, and empty-selection behavior. Use a temporary Application Support directory and assert old JSON bytes remain unchanged after a new status revision.

  ```swift
  func testInstallRoundTripsOnlyForExactRevision() throws {
      let store = try FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
      let snapshot = fixtureSnapshot(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))
      try store.install(snapshot)
      XCTAssertNotNil(try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))))
      XCTAssertNil(try store.load(matching: fixtureRevision(status: .finished, updatedAt: Date(timeIntervalSince1970: 10))))
  }
  ```

- [ ] Step 2: Run RED. Expected RED: the sidecar types and exact-revision reader do not exist.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/NutrientImpactSidecarTests -only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests
  ```

- [ ] Step 3: Implement the sidecar with `schemaVersion == 1`, canonical catalog/factory copy and disclaimer rules for all six statuses, deterministic canonical fingerprint, safe filename, atomic install/read-back, exact active revision matching, and orphan-tolerant reads. Build alternatives only through the typed same-day selector; require current/allergy filtering, structured nutrient overlap, deterministic priority, provenance matching, and at most two unique labels. Keep direct sidecar validation structural-only (canonical whitespace/NFC, bounds, controls/format/path separators, and duplicate rejection), without semantic quantity/secret/medical/action inference. Do not add a Core Data attribute or call any migration/backfill path.
- [ ] Step 4: Run GREEN and verify the public v1 model exact test, malformed/path traversal/forbidden-copy handling, restart read-back, and no matching read for an orphan or stale revision.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/NutrientImpactSidecarTests -only-testing:NaymNaymLevelUpTests/RebuildPersistentStoreTests
  ```

- [ ] Step 5: Commit the sidecar-only persistence primitive.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Meal/NutrientImpactSidecar.swift NaymNaymLevelUp/Rebuild/Meal/MealDomain.swift NaymNaymLevelUp/Rebuild/Meal/NutritionRuleEngine.swift NaymNaymLevelUpTests/NutrientImpactSidecarTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
  git commit -m "feat: store nutrition guidance by meal revision"
  ```

### Task 6: Unify allergy safety and single active meal records

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Meal/RecordMealUseCase.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestViewModel.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/NutrientImpactSidecar.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift`
- Modify: `NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests.swift`
- Modify: `NaymNaymLevelUpTests/TodayForestViewModelTests.swift`

**Interfaces:**
- Add one pure shared policy used by both UI and use case:

  ```swift
  enum MealSafetyPolicy {
      static func allowedStatuses(childAllergyCodes: Set<Int>, itemAllergyCodes: Set<Int>) -> Set<RebuildEatingStatus>
      static func validate(childAllergyCodes: Set<Int>, itemAllergyCodes: Set<Int>, status: RebuildEatingStatus) throws
  }
  ```

- Extend `RecordMealCommand` with an optional `nutritionSnapshot` defaulting to nil and inject `any NutrientImpactSidecar` into `RecordMealUseCase` with the existing no-op default. Before the Core Data save, resolve the current active record by `date + normalizedMenuName`, rebind the immutable snapshot to the actual record ID/status/`occurredAt`, install/read back the sidecar, then update the existing row. For a status change retain the row ID/photos/sourceRecordID, set the old duplicate rows’ `deletedAt`, and never issue another XP event for the same logical meal.
- Keep legacy status-based rows/events readable for migration and award checks. New active identity is `date|normalizedMenuName`; the status is data, not identity. Existing 1.1 rows are never physically deleted.

- [x] Step 1: Update/add tests named `testAllSixStatusesArePresented`, `testAllergyRiskAllowsOnlyAllergyAvoidedAndGuardianCheck`, `testAllergySafetyIsRejectedBeforePersistence`, `testStatusTransitionLeavesOneActiveRecordAndOneAwardEvent`, `testStatusTransitionPreservesPhotosAndSourceRecordID`, `testNutritionReviewCancelWritesNothing`, `testSidecarInstallOccursBeforeCoreDataTransaction`, `testSidecarFailureDoesNotWriteRecordOrXP`, and `testCoreDataFailureLeavesNoMatchingActiveRevision`. Add a regression for the user-facing `오늘은 안 먹어요` label while retaining raw `difficultToday`.

  ```swift
  func testStatusTransitionLeavesOneActiveRecordAndOneAwardEvent() throws {
      try useCase.execute(command(status: .oneBite))
      _ = try useCase.execute(command(status: .finished, recordID: "2026-08-12|시금치나물"))
      XCTAssertEqual(try activeRecords(date: "2026-08-12", menu: "시금치나물").count, 1)
      XCTAssertEqual(try mealEvents(date: "2026-08-12", menu: "시금치나물").count, 1)
  }
  ```

- [x] Step 2: Run RED against existing tests. Expected RED: `half` is not exposed in Today, allergy UI permits a status that use case rejects, and status-based IDs produce multiple active rows/events.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests -only-testing:NaymNaymLevelUpTests/TodayForestViewModelTests
  ```

- [x] Step 3: Implement `MealSafetyPolicy`, six-state labels, allergy-safe disabled states and separate guardian CTA. Update `RecordMealUseCase` validation and active-row lookup without changing Core Data schema. Install a frozen sidecar before save; if save fails, rollback Core Data and leave only an unreadable orphan. Preserve photos, parent-share flag, existing sourceRecordID, and one award event.
- [x] Step 4: Run GREEN and verify UI and persistence use the same allowed set, cancel before confirmation has no writes, status edits do not double XP, allergy avoidance has no penalty, and old rows remain queryable but inactive.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests -only-testing:NaymNaymLevelUpTests/TodayForestViewModelTests
  ```

- [x] Step 5: Commit the safety/record transaction change.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Meal/RecordMealUseCase.swift NaymNaymLevelUp/Rebuild/Child/TodayForestViewModel.swift NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift NaymNaymLevelUp/Rebuild/Meal/NutrientImpactSidecar.swift NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift NaymNaymLevelUpTests/RebuildRecordMealUseCaseTests.swift NaymNaymLevelUpTests/TodayForestViewModelTests.swift
  git commit -m "feat: unify meal safety and active record revisions"
  ```

### Task 7: Finish the shared detail/recording UI and accessibility behavior

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Foundation/RebuildDesignTokens.swift`
- Modify: `NaymNaymLevelUpTests/RebuildDesignTokensTests.swift`
- Modify: `NaymNaymLevelUpTests/MealScheduleSelectionTests.swift`
- Modify: `NaymNaymLevelUpTests/TodayForestViewModelTests.swift`

**Interfaces:**
- `MealDayDetailView` exposes stable identifiers `meal_day_detail_<dateKey>`, `meal_day_status`, `meal_day_menu_<normalizedName>`, `meal_day_nutrition`, and `meal_day_record_cta`.
- `MealRecordingSheet` scopes every per-menu control identifier with `<menuIndex>_<normalizedMenuToken>`: `meal_recording_status_<menuIndex>_<normalizedMenuToken>_<rawValue>`, `meal_allergy_safe_choice_<menuIndex>_<normalizedMenuToken>`, and `meal_guardian_check_<menuIndex>_<normalizedMenuToken>`. It also exposes `meal_recording_nutrition_review` and `meal_recording_confirm`. Its flow is status → optional difficult reason → representative impact review → confirm/save → XP result.
- Add semantic colors to existing `RebuildDesignTokens` only (`growth`, `mission`, `appetite`, `nutrition`, `schedule`, `safety`, `background`) and keep existing hex values/spacing/radii/minimum action size as the base contract.

- [x] Step 1: Add tests `testDetailAccessibilityOrderIsDateStateMenuAllergyNutritionCTA`, `testRecordingReviewAppearsBeforeAnyWrite`, `testLargeContentSizeKeepsStatusActionsReachable`, `testReduceMotionUsesStaticResult`, `testAllergyStateUsesTextIconAndShape`, and `testSemanticTokensKeepMinimumContrast`. Assert all identifiers and 48pt minimum frames in the view inspection/presentation model.
- [x] Step 2: Run RED. Expected RED: the current recording sheet writes immediately on status tap, does not expose half, and detail/accessibility identifiers and semantic token cases are incomplete.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealScheduleSelectionTests -only-testing:NaymNaymLevelUpTests/TodayForestViewModelTests -only-testing:NaymNaymLevelUpTests/RebuildDesignTokensTests
  ```

- [x] Step 3: Refactor only the existing views: show menu previews before selection, put selected-date data and full nutrition totals in the shared detail, render icon/name/allergy/chips, keep difficult reason conditional, and require an explicit confirm after the safe impact review. Use semantic tokens, system fonts, labels plus icons/shapes, Dynamic Type without fixed 10pt text, and Reduce Motion static mascot/result.
- [x] Step 4: Run GREEN with the focused suites and manual accessibility environment checks (`UIContentSizeCategory.accessibilityExtraExtraExtraLarge`, VoiceOver order, Reduce Motion, Increase Contrast). Verify no selected-date fallback or immediate write remains.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealScheduleSelectionTests -only-testing:NaymNaymLevelUpTests/TodayForestViewModelTests -only-testing:NaymNaymLevelUpTests/RebuildDesignTokensTests
  ```

- [x] Step 5: Commit the user-facing detail and accessibility UI.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Child/MealDayDetailView.swift NaymNaymLevelUp/Rebuild/Child/MealScheduleView.swift NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift NaymNaymLevelUp/Rebuild/Child/MealRecordingSheet.swift NaymNaymLevelUp/Rebuild/Foundation/RebuildDesignTokens.swift NaymNaymLevelUpTests/RebuildDesignTokensTests.swift NaymNaymLevelUpTests/MealScheduleSelectionTests.swift NaymNaymLevelUpTests/TodayForestViewModelTests.swift
  git commit -m "style: polish meal detail and accessible recording flow"
  ```

### Task 8: Validate assets, growth visuals, and design-system fallbacks

**Files:**
- Modify: `NaymNaymLevelUp/Rebuild/Growth/GrowthView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Growth/CollectionView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigModel.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Mascot/MascotRigView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift`
- Modify: `NaymNaymLevelUp/Resources/Assets.xcassets` (only rights-verified stage/icon assets)
- Modify: `NaymNaymLevelUp/Resources/MascotRig` (only rights-verified 8–12 layers; otherwise no new files)
- Create: `docs/CHARACTER_ASSET_MANIFEST.md`
- Create: `docs/MEAL_ICON_ASSET_MANIFEST.md`
- Modify: `THIRD_PARTY_NOTICES.md` (only when a new licensed asset is actually bundled)
- Create: `NaymNaymLevelUpTests/AssetManifestTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj` (add test/source resources only when files exist)

**Interfaces:**
- `MascotRigLoader` remains the source of truth for verified parts. `GrowthView`/`CollectionView` request a stage asset key; missing/invalid 8–12 assets return a neutral, non-crashing fallback with accessible text, not a fake finished character.
- Every food category key resolves either to an existing bundled asset listed in `MEAL_ICON_ASSET_MANIFEST.md` or to explicit `food.other` SF Symbol fallback. Every new file records origin, creator/generation path, license, source URL/internal source, and modification status.

- [x] Step 1: Add failing `AssetManifestTests` cases `testStagesOneThroughTwelveHaveDeterministicAssetResolution`, `testMissingStageAssetReturnsNeutralFallback`, `testFoodIconManifestContainsEveryResolverKey`, and `testUnlicensedOrUntrackedAssetIsRejected`. Extend existing `MascotMotionControllerTests`/`LocalStoreTests` to assert existing 1–7 names and first-party Lottie files are unchanged.
- [x] Step 2: Run RED. Expected RED: no manifest covers new stage/icon keys and current 8–12 lookup is an implicit 7-stage reuse.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/AssetManifestTests -only-testing:NaymNaymLevelUpTests/MascotMotionControllerTests -only-testing:NaymNaymLevelUpTests/LocalStoreTests
  ```

- [x] Step 3: Add only rights-verified 8–12 artwork if available; otherwise encode neutral fallback and document the limitation. Update growth/collection to use actual policy count, 2-column grid, stage name/threshold/reward, lock text and accessibility labels. Keep the existing 1–7 MascotRig names, forest layers, Lottie package and no new animation engine.
- [x] Step 4: Run GREEN, inspect all manifest paths and checksums, and confirm fallback does not affect data/XP or crash when an asset is absent.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/AssetManifestTests -only-testing:NaymNaymLevelUpTests/MascotMotionControllerTests -only-testing:NaymNaymLevelUpTests/LocalStoreTests
  rg -n "14단계|캐릭터 14|stage.*14|level.*14" NaymNaymLevelUp docs release README.md || true
  ```

- [x] Step 5: Commit the visual asset/fallback contract.

  ```bash
  git add NaymNaymLevelUp/Rebuild/Growth NaymNaymLevelUp/Rebuild/Mascot NaymNaymLevelUp/Rebuild/Meal/MealPresentation.swift NaymNaymLevelUp/Resources/Assets.xcassets NaymNaymLevelUp/Resources/MascotRig docs/CHARACTER_ASSET_MANIFEST.md docs/MEAL_ICON_ASSET_MANIFEST.md THIRD_PARTY_NOTICES.md NaymNaymLevelUpTests/AssetManifestTests.swift NaymNaymLevelUpTests/MascotMotionControllerTests.swift NaymNaymLevelUpTests/LocalStoreTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
  git commit -m "style: validate growth and meal visual fallbacks"
  ```

### Task 9: Execute device QA and capture release-quality screenshots

**Files:**
- Create: `build/verification/growth-meal-polish-v2/` (ignored QA artifacts; never commit)
- Create: `build/verification/growth-meal-polish-v2/before/` and `after/` screenshot sets
- Create: `build/verification/growth-meal-polish-v2/device-qa-report.md` (ignored report)
- Create: `docs/qa/growth-meal-polish-v2-device-qa.md` (tracked device/coverage summary)
- Use: `NaymNaymLevelUp.xcodeproj`, existing `Codex Clean iPhone 17 Pro` simulator, and any compatible iPhone 16/SE-class simulators created below

**Interfaces:**
- QA launches the same Rebuild scheme/build tested by XCTest and uses stable accessibility identifiers from Tasks 3/7. No screenshot is evidence of an App Store upload.
- Required screenshot filenames: `01_home_character_growth.jpg`, `02_today_meal_icons.jpg`, `03_weekly_meal.jpg`, `04_monthly_meal.jpg`, `05_selected_day_detail.jpg`, `06_eating_status_picker.jpg`, `07_nutrient_impact_skipped.jpg`, `08_nutrient_impact_one_bite.jpg`, `09_allergy_safe_choice.jpg`, `10_growth_stage_roadmap.jpg`, `11_growth_next_unlock.jpg`, `12_parent_growth_summary.jpg`, `13_iphone_se_day_detail.jpg`, `14_iphone_se_growth.jpg`, `15_appstore_lead_candidate.jpg`.

- [ ] Step 1: Record the baseline devices and create only supported types/runtimes. Use the existing 17 Pro regardless; when both a device type and runtime are listed, create iPhone 16 and SE-class devices and record their UDIDs. If a type/runtime is absent, write the exact missing identifier/runtime to `device-qa-report.md` and do not fabricate a result.

  ```bash
  xcrun simctl list runtimes available
  xcrun simctl list devicetypes available | rg 'iPhone 16|iPhone SE'
  runtime_id="$(xcrun simctl list runtimes available | awk -F '[()]' '/iOS 26/ {print $2; exit}')"
  iphone16_type="$(xcrun simctl list devicetypes available | awk -F '[()]' '/iPhone 16 / {print $2; exit}')"
  se_type="$(xcrun simctl list devicetypes available | awk -F '[()]' '/iPhone SE/ {print $2; exit}')"
  if [[ -n "$runtime_id" && -n "$iphone16_type" ]]; then xcrun simctl create "Growth QA iPhone 16" "$iphone16_type" "$runtime_id"; fi
  if [[ -n "$runtime_id" && -n "$se_type" ]]; then xcrun simctl create "Growth QA iPhone SE" "$se_type" "$runtime_id"; fi
  xcrun simctl list devices available
  ```

- [ ] Step 2: Build and launch Debug on iPhone 17 Pro, then repeat on created iPhone 16/SE devices when available. Use the app’s explicit scheme/configuration and capture before/after where a baseline screen exists.

  ```bash
  xcodebuild build -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData
  xcrun simctl bootstatus 5D3D62C5-12A4-49A3-8D44-F513FCEAFDED -b
  xcrun simctl install 5D3D62C5-12A4-49A3-8D44-F513FCEAFDED build/verification/growth-meal-polish-v2/DerivedData/Build/Products/Debug-iphonesimulator/NaymNaymLevelUp.app
  xcrun simctl launch 5D3D62C5-12A4-49A3-8D44-F513FCEAFDED com.h19h29.naymnaymlevelup
  ```

- [ ] Step 3: Exercise and record these screens/states: home; today; weekly; monthly; selected-day detail; each six-state picker; skipped-menu and one-bite impact; allergy-safe choice; 12-stage roadmap; next unlock; parent summary; empty meal; API failure; explicit experience mode. Verify no real API failure becomes sample data and no secret/personal data appears in a screenshot.
- [ ] Step 4: Capture the required names at native simulator resolution, inspect manually at normal/max Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast, and iPhone SE width. Store device IDs, OS, build number, state, and any unsupported-device limitation in both `build/verification/growth-meal-polish-v2/device-qa-report.md` and the tracked `docs/qa/growth-meal-polish-v2-device-qa.md`.
- [ ] Step 5: Run the visual/interaction test suites after capture and do not commit the `build/verification` directory.

  ```bash
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData -only-testing:NaymNaymLevelUpTests/MealScheduleSelectionTests -only-testing:NaymNaymLevelUpTests/MealPresentationTests -only-testing:NaymNaymLevelUpTests/AssetManifestTests
  git status --short --ignored build/verification/growth-meal-polish-v2
  ```

- [ ] Step 6: Commit the tracked device/coverage summary only; leave simulator binaries and screenshots under `build/verification` ignored.

  ```bash
  git add docs/qa/growth-meal-polish-v2-device-qa.md
  git commit -m "qa: record growth meal polish device validation"
  ```

### Task 10: Align metadata/docs and perform final no-upload verification

**Files:**
- Modify: `release/AppStoreMetadata/ko-KR.md`
- Modify: `release/AppStoreMetadata/app-store-connect-values.json`
- Modify: `release/AppStoreMetadata/submission-notes.md`
- Modify: `release/AppStoreMetadata/console-runbook.md` (remove stale 1.0/old-build instructions from the local runbook only)
- Modify: `docs/APP_STORE_METADATA.md`
- Modify: `README.md`
- Modify: `scripts/verify-release-readiness.sh`
- Modify: `NaymNaymLevelUp/Resources/Animations/README.md` only if fallback/asset documentation changed
- Verify without staging: `Config.xcconfig`, `Package.resolved`, `build/`, `.superpowers/sdd/*`

**Interfaces:**
- Metadata must describe the actual candidate marketing version/build already in the Xcode project (baseline `1.2`/`33`) and the implemented 12-stage/date-detail/nutrition/icon/accessibility behavior. It must retain the allergy disclaimer, local-only photo statement, privacy draft, and no-ad/no-tracking claims only when verified.
- `scripts/verify-release-readiness.sh` must accept candidate version/build explicitly, validate local Debug/Release artifacts and metadata, and skip signed IPA/upload-log assertions when `RELEASE_UPLOAD_REQUIRED=0` (the value used here). It must never turn “no App Store upload” into an upload operation.

- [ ] Step 1: Add a documentation/readiness regression before changing the files: assert the metadata JSON/Markdown all say `급식레벨업`, bundle `com.h19h29.naymnaymlevelup`, candidate `1.2`/`33`, exact 12-stage copy, selected-date detail, safe representative nutrition copy, and no App Store submission. Add a shell test invocation or a deterministic Ruby/Python check in the existing verification script; do not embed secrets.

  ```bash
  EXPECTED_MARKETING_VERSION=1.2 EXPECTED_BUILD_NUMBER=33 RELEASE_UPLOAD_REQUIRED=0 bash scripts/verify-release-readiness.sh
  ```

  Expected RED before implementation: the current script checks old 1.0/uploaded IPA values and current metadata is 1.1/build30.

- [ ] Step 2: Update the three requested App Store material files plus stale local metadata docs and README copy. Add the four approved release messages: “캐릭터 성장 단계가 12단계로 늘어났어요.”, selected-date weekly/monthly detail, 부담 없는 representative nutrient education, and improved menu icons/design. Do not click or call App Store Connect.
- [ ] Step 3: Update the readiness script only to parameterize candidate version/build, make local archive/export checks explicit, preserve bundle/entitlement/privacy/license/secret checks, and gate all upload-log/IPA assertions behind `RELEASE_UPLOAD_REQUIRED=1`. Keep project settings unchanged; do not alter `Config.xcconfig` or upload credentials.
- [ ] Step 4: Run final GREEN verification in this order and save output under ignored `build/verification/growth-meal-polish-v2/`:

  ```bash
  python3 -m unittest discover -s scripts/tests
  bash scripts/validate-native-rebuild-contracts.py
  bash scripts/sync-native-rebuild-contracts.sh
  xcodebuild test -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Debug -destination 'platform=iOS Simulator,id=5D3D62C5-12A4-49A3-8D44-F513FCEAFDED' -derivedDataPath build/verification/growth-meal-polish-v2/DerivedData
  xcodebuild build -project NaymNaymLevelUp.xcodeproj -scheme NaymNaymLevelUp -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/verification/growth-meal-polish-v2/ReleaseDerivedData CODE_SIGNING_ALLOWED=NO
  EXPECTED_MARKETING_VERSION=1.2 EXPECTED_BUILD_NUMBER=33 RELEASE_UPLOAD_REQUIRED=0 bash scripts/verify-release-readiness.sh
  git diff --check
  git status --short
  ```

- [ ] Step 5: Run the final secret/scope audit. It must report no tracked `Config.xcconfig`, API key/token/private key/certificate material, or `.superpowers` scratch report; only the tracked design spec and this plan are allowed in the documentation-only planning commit now, and implementation commits must contain only their task files.

  ```bash
  git diff --name-only --cached
  git ls-files | rg '(^|/)(Config\.xcconfig|.*\.(p8|p12|mobileprovision|pem|key))$' || true
  rg -n --hidden --glob '!build/**' --glob '!.git/**' --glob '!.superpowers/sdd/**' '(NEIS_API_KEY|SUPABASE_SERVICE_ROLE|PRIVATE KEY|api[_-]?key[[:space:]]*=)' . || true
  git diff --check
  ```

- [ ] Step 6: Commit and push only after all Debug/Release/full-test/device/readiness checks pass. This is the final implementation branch handoff; stop before App Store Connect upload or App Review submission.

  ```bash
  git add release/AppStoreMetadata/ko-KR.md release/AppStoreMetadata/app-store-connect-values.json release/AppStoreMetadata/submission-notes.md release/AppStoreMetadata/console-runbook.md docs/APP_STORE_METADATA.md README.md scripts/verify-release-readiness.sh NaymNaymLevelUp/Resources/Animations/README.md
  git commit -m "docs: align growth meal polish release materials"
  git push -u origin codex/ios-growth-meal-polish-v2
  ```

  If push needs GitHub login/2FA, retain the local commit and report the exact authentication blocker; do not paste credentials or retry by storing them in the repository.
