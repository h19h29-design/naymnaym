# 성장·급식 경험 개선 v2 설계

- 상태: 승인됨
- 작성일: 2026-08-30
- 구현 기준: 최신 iOS Rebuild 1.2 후보
- 호환 기준: 공개 App Store 1.1
- 대상 번들: com.h19h29.naymnaymlevelup
- 관련 감사: docs/UX_AUDIT_2026-08-30.md

## 1. 결정 요약

최신 Rebuild 후보를 유지하고 기존 도메인·저장소·정책 로더·화면을 최소 확장한다. 새로운 앱 구조나 별도 디자인 시스템을 만들지 않는다.

핵심 결정은 다음과 같다.

1. 성장 단계는 정확히 12개다.
2. 공개된 1–7 이름과 임계값 0, 80, 180, 320, 500, 720, 1000 XP는 바꾸지 않는다.
3. 8–12 임계값은 1300, 1650, 2050, 2500, 3000 XP다.
4. XP 원장과 사용자 기록은 그대로 두고 현재 단계를 정책에서 다시 계산한다.
5. 미출시 14단계 후보는 마이그레이션 원본이 아니라 편집 원본이다. 8–14의 소재를 8–12에 통합한다.
6. 성장 상태는 변경하지 않은 Core Data v1과 migration state를 그대로 두고, bounded `growth-stage-state-v2` UserDefaults 값만 단조 증가 방식으로 추가한다. 기존 UserDefaults 진행 값은 읽기 전용 권리 하한으로 union한다.
7. 영양 안내는 Core Data 열이나 v2 backfill이 아니라 정확한 meal-record revision에 결합된 versioned immutable sidecar로 보존한다.
8. 오늘·주간·월간은 같은 MealDayDetailView와 정확한 dateKey를 사용한다.
9. 기존 NutritionRuleEngine을 확장해 대표 영양소 피드백을 제공한다. 개별 메뉴의 정량 영양값은 추정하지 않는다.
10. 알레르기 안전 규칙은 선택 UI와 RecordMealUseCase가 동일한 정책을 사용한다.
11. 기존 1–7 마스코트, 숲 레이어, 디자인 토큰, Core Data 엔티티를 재사용한다.

## 2. 진실 공급원

서로 다른 문서와 후보가 충돌할 때 아래 순서를 따른다.

| 영역 | 진실 공급원 | 역할 |
|---|---|---|
| 런타임 구조 | 최신 Rebuild 후보의 Swift 소스와 Rebuild 계약 JSON | 구현 출발점 |
| 공개 호환성 | App Store 1.1과 legacy PlayerProgress/LocalStores | 보존해야 할 사용자 데이터 |
| 성장 단계 | 이 문서의 12단계 표와 변경된 growth-policy.json | 단계 수·이름·임계값 |
| 급식 데이터 | RebuildMealDay/RebuildMealItem과 저장된 원문·NEIS 응답 | 선택 날짜의 메뉴·알레르기·전체 급식 영양 |
| 에셋 권리 | 저장소의 첫 제작 출처 기록, THIRD_PARTY_NOTICES, 새 에셋 manifest | 배포 가능 여부 |
| 시각 참고 | 현재 공개 스크린샷과 승인된 방향 | 화면 위계 참고 |

docs/qa/collection-v12-figma-record.md의 14단계 보드는 과거 후보 기록이다. 단계 수나 콘텐츠의 구현 진실이 아니며 Figma와 코드가 다르면 이 문서와 테스트가 우선한다.

README의 Release 플래그 설명, 1.1 릴리스 메타데이터, Xcode 1.2/build 33 값도 현재 서로 다른 시점을 나타낸다. 이 설계 단계에서는 수정하지 않지만 출하 체크에서 반드시 함께 비교한다.

## 3. 목표와 성공 조건

### 사용자 목표

- 오늘 먹을 메뉴와 할 행동을 빠르게 이해한다.
- 주간·월간에서 고른 날짜의 실제 급식을 같은 상세 화면에서 본다.
- 기록한 식사와 대표 영양소의 관계를 쉽고 안전한 문장으로 배운다.
- 성장 단계가 실제로 달라지는 모습을 보고 다음 목표를 이해한다.
- 기존 기록과 성장이 업데이트 뒤에도 그대로 남아 있다고 신뢰한다.

### 제품 성공 조건

- 12단계 계약과 UI가 단일 값을 사용한다.
- 공개 1.1 데이터 마이그레이션 전후 손실이 0건이다.
- 선택 dateKey와 상세 dateKey 불일치가 0건이다.
- 동일 날짜·메뉴에 활성 상태가 하나만 존재한다.
- 알레르기 위험 메뉴에서 허용되지 않는 저장 요청이 UI를 통과하지 않는다.
- 대표 영양 피드백에 메뉴별 추정 g, mg, kcal가 없다.
- Dynamic Type, VoiceOver, Reduce Motion, iPhone SE 폭을 통과한다.

## 4. 재사용 지도

Ponytail 원칙에 따라 이미 있는 코드와 타입을 우선 사용한다.

| 요구 | 재사용할 현재 자산 | 필요한 최소 변경 |
|---|---|---|
| 성장 계산 | GrowthPolicy, GrowthPolicyLoader, GrowthViewModel, growth-policy.json | 12단계 계약·카피·테스트 교체; legacy `PlayerProgress`의 공개 1–7 계산 계약은 유지 |
| XP 보존 | RebuildProgressEvent, RebuildProgressRepository | 원장 불변 검증 추가 |
| 성장 권리 저장 | `LegacyDefaultsReader`, `ProgressStore`의 read-only raw payload, bounded `growth-stage-state-v2` UserDefaults store | XP 단계·유효 legacy level/skin·저장된 최고 해금 단계를 단조 증가 union; Core Data와 v1 migration state는 변경하지 않음 |
| 공개 데이터 이관 | LegacyDefaultsReader, RebuildMigrationCoordinator, migration state/digest | 기존 v1 이관을 재실행하거나 v2 backfill하지 않고, raw progress 권리·배지·스킨 보존 검증 추가 |
| 성장 화면 | GrowthView, CollectionView, CollectionProgress | 12단계 로드맵, 2열 도감, 선택 상세 |
| 마스코트 | Squirrel_Growth_Level_1…7, MascotRig level_01…07, forest layers | 8–12 첫 제작 레이어 추가와 안전한 대체 |
| 날짜 계산 | MealScheduleCalendar | 월–일 7일, dateKey 헬퍼 보강 |
| 급식 조회 | RebuildMealRepository, MealLoadState, RebuildMealDay/RebuildMealItem | 선택 날짜 상태를 상세까지 전달 |
| 급식 화면 | MealScheduleView, TodayForestView, 기존 legacy MealDayPreview/Detail의 상호작용 패턴 | Rebuild 공통 MealDayDetailView 추출 |
| 기록 상태 | RebuildEatingStatus, MealRecordingSheet, RecordMealUseCase | half 노출, 확인 단계, 활성 기록 단일화 |
| 영양 규칙 | NutritionRuleEngine, NutritionInsight, nutrition-rules.json | 분류·확신도·대체 메뉴·저장 스냅샷 확장 |
| 알레르기 | 프로필 allergyCodes, 메뉴 allergyCodes, 현재 저장 검증 | 공유 SafetyPolicy로 UI/유스케이스 통일 |
| 색·타이포 | RebuildDesignTokens, legacy AppColors의 검증된 색 값 | 의미 색과 컴포넌트 상태만 추가 |
| 영양 안내 저장 | 기존 RebuildMealRecord revision 필드 + Application Support sidecar | immutable, versioned snapshot을 정확한 record revision fingerprint에 결합; Core Data 열 추가 없음 |
| 저장 모델 | RebuildProfile, RebuildMealRecord | 기존 Core Data v1 스키마와 migration state를 그대로 유지 |

새 GrowthSystem, MealPlatform, NutritionService 계층을 만들지 않는다. 화면에서 사용하는 가벼운 조합 타입은 허용하되 저장소와 네트워크 추상화를 복제하지 않는다.

## 5. 성장 정책

### 5.1 최종 12단계

| 단계 | 시작 XP | 이름 | 시각 모티프 |
|---:|---:|---|---|
| 1 | 0 | 냠냠 새싹 | 새싹과 작은 잎 |
| 2 | 80 | 한 입 탐험가 | 탐험 손수건 |
| 3 | 180 | 냠냠 용사 | 작은 용기 배지 |
| 4 | 320 | 편식 몬스터 사냥꾼 | 방패와 몬스터 발자국 |
| 5 | 500 | 급식 히어로 | 히어로 망토 |
| 6 | 720 | 영양 마스터 | 영양 별 장식 |
| 7 | 1000 | 레전드 냠냠러 | 공개 1.1 레전드 모습 |
| 8 | 1300 | 별빛 셰프 | 별빛 모자와 저녁 숲 |
| 9 | 1650 | 균형 수호자 | 균형 식판 문양 |
| 10 | 2050 | 숲의 영양 기사 | 잎 방패와 깊은 숲 |
| 11 | 2500 | 황금 한입 챔피언 | 황금 도토리·한입 메달 |
| 12 | 3000 | 전설의 급식대장 | 완성 왕관과 축제 숲 |

정책 로더는 정확히 12개, 엄격히 증가하는 임계값, 고유한 제목, 1–7 고정값을 검증한다. 마지막 단계는 상한이 없다. 3000 이상 모든 XP는 12단계로 표시하되 실제 XP 숫자는 그대로 보여 준다.

### 5.2 미출시 14단계 후보의 편집 방식

현재 후보의 8–14 콘텐츠는 사용자 데이터가 아니라 아직 공개되지 않은 정책·카피다. 다음처럼 소재를 압축한다.

| 14단계 후보 소재 | 12단계에서의 사용 |
|---|---|
| 숲길 수호자 | 10단계 숲의 영양 기사 배경·방패에 통합 |
| 제철 탐험대장 | 계절 숲 장식 또는 제철 컬렉션 배지로 이동 |
| 균형 식판 장인 | 9단계 균형 수호자의 핵심 소재로 유지 |
| 초록별 수호대장 | 8단계 별빛과 10단계 숲 소재에 분리 통합 |
| 영양 수호대장 | 10단계 이름·보상에 통합 |
| 황금 도토리 대장 | 11단계 황금 한입 챔피언의 핵심 소재로 유지 |
| 급식 전설 | 12단계 전설의 급식대장의 핵심 소재로 유지 |

삭제되는 사용자 XP나 기록은 없다. 내부 14단계 빌드를 사용했던 데이터가 있더라도 저장된 것은 XP 원장이고 단계는 파생값이므로 같은 XP를 새 12단계 정책에 매핑한다. 예를 들어 4850 XP는 12단계이지만 XP는 4850 그대로다.

### 5.3 단계 표시와 선택

- 현재 XP 단계는 변경하지 않은 `RebuildProgressEvent` 원장의 기존 합계 의미에서 매번 파생한다.
- 다음 목표는 다음 임계값까지 남은 XP로 계산한다.
- bounded `growth-stage-state-v2` UserDefaults payload에는 `version`, `highestUnlockedStageID`, `selectedStageID`만 Codable로 저장한다. 누락·부분·범위를 벗어난 값은 안전한 기본값으로 읽는다.
- `highestUnlockedStageID`는 XP 단계, raw legacy `level`, 유효한 `skin-1…skin-7` 단계, 저장된 최고 해금 단계의 최대값을 `1...12`로 clamp한 값이며, 이전 값보다 낮게 저장하지 않는다.
- `selectedStageID`는 이미 해금된 유효 단계만 사용한다. 없거나 잠겨 있으면 유효한 legacy skin 선택, 그 다음 최고 해금 단계 순으로 표시한다. 새 후반 단계를 활성 스킨으로 선택하는 기능은 추가하지 않는다.
- 공개 선택 스킨 `skin-1…skin-7`과 legacy badge 문자열은 `player-progress` 원본에서 읽기 전용 권리로 union하며, legacy 원본을 재인코딩하거나 삭제하지 않는다.
- 에셋이 없거나 로드에 실패하면 현재 XP와 단계명은 유지하고 가장 높은 검증된 1–7 기본 몸체와 중립 프레임을 사용한다. 대체 표시를 새 완성 캐릭터로 표현하지 않는다.

### 5.4 성장 권리 저장·롤백 계약

성장 권리는 기존 Core Data v1 스키마와 `RebuildMigrationState` version/digest를 건드리지 않는다. v1 migration을 재실행하거나 별도의 v2 backfill을 수행하지 않는다. `growth-stage-state-v2`는 파생된 표시 권리를 빠르게 복원하기 위한 bounded additive cache일 뿐이며, 쓰기 실패 시 XP 원장과 read-only legacy 권리로 다시 계산한다.

권리 계산은 다음과 같다.

```text
xpStage = stage(totalXP from unchanged RebuildProgressEvent semantics)
legacyLevel = valid raw player-progress.level, else 1
legacySkinStage = valid skin-1...skin-7 suffix, else 1
storedHighest = valid growth-stage-state-v2.highestUnlockedStageID, else 1
highestUnlocked = clamp(max(xpStage, legacyLevel, legacySkinStage, storedHighest), 1...12)
selected = valid stored selectedStageID <= highestUnlocked
        ?? valid legacy skin stage <= highestUnlocked
        ?? highestUnlocked
```

The raw `player-progress` payload is never written as part of this calculation. A malformed or partially written v2 payload must not alter XP, records, badges, skins, parent links, or the legacy defaults bytes. On rollback to 1.1, the old bundle may display only its seven-stage view; the new v2 key remains unknown to it and is read again when the updated bundle returns.

## 6. 저장과 마이그레이션

### 6.1 불변 조건

아래 조건은 기능보다 먼저 테스트로 고정한다.

1. legacy recordExp + challengeExp + balanceExp + safetyExp 합계와 이관 뒤 progress event 합계가 정확히 같다.
2. 기존 Rebuild 원장의 event id, amount, occurredAt, sourceRecordID를 단계 변경 때문에 수정하지 않는다.
3. 같은 XP에서 공개 1.1의 단계보다 낮은 단계가 되지 않는다.
4. meal record, photo 상대 경로, challenge, parent link, share flag의 개수와 식별자가 보존된다. Rebuild에 직접 대응 엔티티가 없는 challenge 상세는 기존 legacy UserDefaults 원본에서 읽으며 별도 v2 backfill을 만들지 않는다.
5. badges 문자열과 currentSkinId를 legacy `player-progress` 원본에서 읽기 전용으로 union하고, 원본 문자열·순서·바이트를 보존한다.
6. skin-1…skin-7 식별자와 공개 이미지 매핑을 바꾸지 않는다.
7. 기존 UserDefaults 원본은 검증 성공만으로 삭제하지 않는다.
8. 검증 실패 시 migration completed를 기록하지 않는다.
9. 영양 스냅샷이 없는 과거 기록은 정상적으로 열리고 필요할 때 현재 규칙으로 “현재 기준 안내”만 만든다.

### 6.2 성장 상태의 최소 additive cache

현재 프로그램식 Core Data 모델, `NaymRebuild.sqlite`, `RebuildMigrationState`의 version/digest와 공개 v1 migration 경로를 **그대로 유지한다**. 새 Core Data 엔티티·속성·모델 버전은 추가하지 않으며, 기존 migration state를 올리거나 v1 migration을 재실행하지 않는다.

bounded UserDefaults 키 `growth-stage-state-v2`만 추가한다. Codable payload는 다음 세 값으로 제한한다.

- `version: Int` (현재 1)
- `highestUnlockedStageID: Int`
- `selectedStageID: Int?`

이 값은 편의상 파생 표시 권리를 캐시할 뿐 XP·기록의 진실 공급원이 아니다. `highestUnlockedStageID`는 읽은 XP 단계, 유효한 raw legacy `player-progress.level`, 유효한 `skin-1…skin-7` 단계, 기존 v2 값의 최대값을 `1...12`로 clamp한 뒤 이전 값보다 낮게 저장하지 않는다. malformed/partial/out-of-range JSON은 무시하고 같은 규칙으로 다시 파생한다. `selectedStageID`는 이미 해금된 유효 단계만 허용하며, 아니면 유효한 legacy skin 선택, 그 다음 최고 해금 단계로 표시한다.

`LegacyDefaultsReader`/`ProgressStore.readPersisted`는 `player-progress`의 level·badges·currentSkinId·XP 구성요소를 읽기 전용으로 제공한다. 원본 UserDefaults payload를 재인코딩·삭제·backfill하지 않는다. CollectionView는 새 파생 배지와 별개로 legacy badge 문자열을 union해 “이전 뱃지”로 보여 주며, 새 컬렉션 수집률 분모에 섞지 않는다. 이 과정은 부모 링크·사진·식사 기록·XP 원장에 쓰지 않는다.

### 6.3 영양 안내 sidecar와 정확한 기록 리비전

영양 안내는 Core Data optional column이나 v2 migration backfill로 저장하지 않는다. Application Support 아래의 전용 sidecar 디렉터리에 **versioned immutable** JSON 파일로 저장하고, 해당 파일은 정확한 meal-record revision에만 결합한다.

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

protocol NutrientImpactSidecar {
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

`recordID + date + normalizedMenuName + status + recordUpdatedAt`로 안전한 결정적 fingerprint/file name을 만들고, 임시 파일 → 원자 rename → 즉시 read-back 검증 순서를 사용한다. Core Data record/event 저장이 실패하면 새 파일은 orphan으로 남아도 읽히지 않으며 기존 matching snapshot은 덮어쓰지 않는다. 상태 변경은 이전 파일을 수정하지 않고 새 revision 파일을 만든다. reader는 현재 활성 Core Data 행의 date/menu/status/updatedAt 및 recordID가 모두 일치할 때만 당시 snapshot으로 인정한다. 일치 파일이 없거나 손상·schema/rule/fingerprint가 다르면 snapshot을 무시하고 “현재 기준 안내”로 명시한다. orphan을 이번 범위에서 적극 삭제하지 않는다.

sidecar에는 교육용 문장과 식별자만 저장하며 메뉴·학교·프로필·부모 연결을 복제하지 않는다. 개별 메뉴의 g/mg/kcal, 의학적 결핍·건강 악화 단정, 알레르기 회피를 번복시키는 권유 문구는 저장 검증에서 거부한다. 기존 `parentShareEnabled`가 true인 record만 기존 공유 정책의 대상이며 새 권한·Supabase schema는 만들지 않는다.

저장 순서는 다음과 같다.

1. UI가 확정한 안전한 command와 frozen snapshot으로 정확한 record revision fingerprint를 만든다.
2. sidecar를 설치하고 read-back/금지 문구 검증을 끝낸다.
3. 기존 `RecordMealUseCase` Core Data record/event transaction을 실행한다.
4. 기록 성공 후 같은 fingerprint를 가진 sidecar를 다시 읽어 당시 안내를 표시한다.

Core Data v1 schema exact test와 v1 migration state exact test는 필수다. sidecar 도입 때문에 model migration이나 v2 backfill을 추가하지 않는다.

## 7. 날짜와 급식 상세

### 7.1 날짜 계약

MealScheduleCalendar의 Gregorian, ko_KR, Asia/Seoul, 월요일 시작 설정을 유지한다. 날짜 식별자는 저장소에서 이미 사용하는 현지 YYYY-MM-DD dateKey로 통일한다.

- day: 선택 dateKey 하나
- week: 선택 날짜가 포함된 월요일부터 일요일까지 7개
- month: 월 그리드의 전체 주, 월요일부터 일요일 열

주말은 흐린 배경과 “주말” 보조 라벨을 쓸 수 있지만 배열에서 제거하지 않는다. 시간대 변환은 정오 기준 임시 날짜를 쓰거나 dateComponents만 사용해 DST·자정 경계 오류를 피한다.

### 7.2 공통 탐색

MealScheduleView의 모든 날짜 선택은 MealDayRoute(dateKey) 하나를 만든다. sheet 또는 NavigationStack의 표현 방식은 기존 화면 구조에 맞추되 payload에 RebuildMealDay 스냅샷을 넣지 않는다.

이유는 두 가지다.

- 같은 날짜가 갱신되면 상세가 저장소의 최신 상태를 관찰해야 한다.
- 메뉴가 아직 로드되지 않았어도 선택 dateKey를 잃지 않고 그 날짜만 조회해야 한다.

TodayForestView 역시 오늘의 dateKey로 같은 상세 조합을 사용한다. legacy의 private MealCalendarDetailSheet를 그대로 복사하지 않고, 날짜를 누르면 상세가 열린다는 검증된 상호작용만 Rebuild에 적용한다.

### 7.3 MealDayDetailView

한 화면의 순서는 다음과 같다.

1. 선택 날짜, 요일, 학교
2. 데이터 상태 배지: 저장됨, 갱신 중, 최신, 급식 없음, 오류
3. 메뉴 아이콘·메뉴명·알레르기 표시·대표 영양소 칩
4. NEIS가 제공한 전체 급식 영양 총량과 출처
5. 식사 기록 CTA

MealDayDetailViewModel은 MealLoadState 자체를 유지한다. RebuildMealDay?만 노출해 상태를 축약하지 않는다.

- cached: 캐시 시각과 새로고침 행동 제공
- refreshing: 기존 캐시를 보여 주며 갱신 상태 표시
- live: 최신 급식 표시
- empty: 해당 날짜에 급식이 없다는 문장
- failed(cached): 캐시가 있으면 유지하고 실패 안내, 없으면 재시도

정확한 선택 날짜에 데이터가 없을 때 오늘 급식이나 monthlyMeals.first를 대신 쓰지 않는다.

### 7.4 주간·월간 밀도

주간:

- 월–일 7개 날짜를 가로 스크롤 또는 폭 대응 카드로 표시한다.
- 좁은 폭에서 메뉴 전문을 7열에 억지로 넣지 않고 대표 아이콘·메뉴 1개·추가 개수만 표시한다.

월간:

- 셀에는 날짜, 상태 점, 대표 메뉴 1개 또는 아이콘, 추가 개수만 표시한다.
- 10pt 고정 글꼴을 사용하지 않는다.
- Dynamic Type가 큰 경우 메뉴명을 숨기고 아이콘·상태만 남기며 상세에서 전체 내용을 제공한다.

## 8. 메뉴 표현과 영양 피드백

### 8.1 메뉴 정규화

현재 normalizedMenuName과 sourceRawText를 보존한다. 표시·분류용 정규화는 다음만 수행한다.

- 알레르기 번호 괄호와 반복 공백 제거
- 조리 기호·원산지 보조 문구 분리
- 원문은 절대 덮어쓰지 않음

정규화 결과는 식별·규칙 매칭에 쓰고 사용자 화면에는 원래 메뉴명을 우선 표시한다.

### 8.2 기존 규칙 엔진 확장

NutritionRuleEngine과 nutrition-rules.json에 다음 필드를 선택적으로 추가한다.

- foodCategory: 밥, 국·찌개, 고기, 생선, 달걀, 콩·두부, 채소, 과일, 유제품, 면, 빵·떡, 김치, 기타
- confidence: exact, keyword, fallback
- iconKey: 배포 manifest에 있는 음식 아이콘 키
- representativeNutrientIDs: 기존 nutrient ID 배열

RebuildMealItem.nutrients에 구조화된 정보가 있으면 그것을 먼저 사용하고, 없을 때만 이름 규칙을 사용한다. 매칭이 없으면 “여러 재료의 영양을 만나는 메뉴예요” 같은 일반 안내와 기타 아이콘을 사용한다.

화면 문구는 대표 유형을 설명한다.

- 허용: “두부에서는 단백질을 만날 수 있어요.”
- 허용: “오늘 한 입으로 채소의 식이섬유를 경험했어요.”
- 금지: “이 메뉴에서 단백질 12g을 먹었어요.”
- 금지: “철분이 부족하니 이 메뉴를 먹어야 해요.”

NEIS가 전체 급식에 제공한 kcal·영양 총량은 “전체 급식 기준”이라는 출처 라벨과 함께 그대로 표시할 수 있지만 개별 메뉴로 나누지 않는다.

### 8.3 상태별 피드백

| 상태 | 피드백 원칙 |
|---|---|
| 다 먹었어요 | 대표 영양소를 만났다는 축하. 완전 섭취·흡수를 단정하지 않음 |
| 절반 먹었어요 | 경험한 대표 영양소를 격려. 절반 수치 계산 금지 |
| 한 입 먹었어요 | 한 입 시도와 감각 경험을 칭찬. 섭취량 계산 금지 |
| 냄새만 맡았어요 | 냄새 탐색을 행동 성취로 표현. 영양 섭취 표현 금지 |
| 오늘은 어려웠어요 | 압박 없는 회고와 같은 급식의 안전한 대체 메뉴 제안 |
| 알레르기로 피했어요 | 안전한 선택을 축하. 영양 손실·실패 문구 금지 |

### 8.4 같은 급식 대체 메뉴

대체 메뉴는 새 네트워크 서비스가 아니라 현재 RebuildMealDay.menuItems 필터다.

1. 현재 메뉴와 같은 normalizedMenuName 제외
2. 프로필 알레르기 코드와 겹치는 메뉴 제외
3. confidence가 fallback뿐인 메뉴보다 구조화 영양 또는 exact 매칭 메뉴 우선
4. 최대 2개, 같은 날짜의 급식 안에서만 제안
5. 안전한 후보가 없으면 제안을 생략

“대체하면 같은 양의 영양을 얻는다”는 표현을 사용하지 않는다.

## 9. 기록 흐름과 알레르기

### 9.1 흐름

MealRecordingSheet는 다음 네 단계만 갖는다.

1. 메뉴와 여섯 상태 선택
2. 어려웠어요인 경우에만 이유 선택
3. 대표 영양 피드백과 알레르기 안전 상태 확인
4. 저장 후 XP 결과

영양 확인 전에는 Core Data와 XP 원장을 변경하지 않는다. 사용자가 취소하면 아무 것도 저장하지 않는다.

### 9.2 공유 안전 정책

MealSafetyPolicy를 순수 함수로 두고 UI와 RecordMealUseCase가 함께 사용한다. 입력은 childAllergyCodes, itemAllergyCodes, eatingStatus다.

알레르기 코드가 겹치면:

- allergyAvoided를 기본·권장 상태로 둔다.
- finished, half, oneBite, smelledOnly, difficultToday는 모두 비활성화한다.
- 보호자에게 확인하는 행동은 식사 상태와 분리된 CTA로 제공한다.
- 영양 손실·실패·벌점 문구를 표시하지 않는다.

저장 계층은 같은 규칙을 다시 검증한다. 알레르기 위험 메뉴에 allergyAvoided 외 상태가 들어오면 저장 전에 명시적 안전 오류를 반환한다. 알레르기 회피에는 XP 패널티를 주지 않는다.

### 9.3 활성 기록 단일성

논리 키는 dateKey + normalizedMenuName이다. 상태는 식별자의 일부가 아니다.

- 기존 활성 기록이 있으면 그 record id를 유지하고 status, reasons, updatedAt을 갱신한다. 영양 snapshot은 해당 revision의 sidecar를 새로 설치하며 Core Data 행에는 저장하지 않는다.
- 과거 상태 기반 id가 여러 개 있으면 updatedAt이 가장 최근인 하나를 현재 기록으로 선택하고 나머지는 deletedAt으로 비활성화한다.
- 행을 물리 삭제하지 않는다.
- 사진 recordID와 기존 progress event sourceRecordID는 다시 쓰지 않는다.
- 새 기록은 논리 키에서 결정적인 id를 만들되 기존 id와 충돌하면 저장소의 현재 기록을 우선한다.
- 이미 sourceRecordID에 연결된 XP 이벤트가 있으면 상태 수정으로 XP를 다시 지급하지 않는다.

화면과 컬렉션 집계는 deletedAt이 nil인 현재 기록만 사용한다. 보호자 이력 화면이 과거 상태를 보여 줄 필요가 생기면 비활성 행을 읽을 수 있지만 이번 범위에서 새 이력 UI는 만들지 않는다.

## 10. 시각 설계

### 10.1 원칙

- 마스코트와 숲을 정체성의 중심으로 유지한다.
- 녹색은 성장·안전·완료에 쓰고 모든 상호작용의 기본색으로 쓰지 않는다.
- 크림 배경 위 카드 반복을 줄이고 배경 구역, 대표 카드, 인라인 행의 세 위계를 사용한다.
- 음식은 텍스트 앞의 56–64pt 대표 아이콘으로 빠르게 인지되게 한다.
- 진행·잠금·위험은 색만으로 구분하지 않는다.

### 10.2 의미 색

legacy AppColors의 검증된 값을 참고해 RebuildDesignTokens 안에 의미 이름으로 추가한다.

| 의미 | 방향 |
|---|---|
| growth/success | forest green, mint |
| mission/action | warm yellow |
| appetite/encouragement | coral |
| nutrition learning | purple, indigo |
| schedule/info | sky blue |
| allergy/safety | danger red + neutral surface |
| background | warm cream |

정확한 색 값은 대비 테스트로 확정한다. 색 이름을 화면 코드에 직접 흩뿌리지 않고 기존 토큰 파일에만 추가한다.

### 10.3 성장 화면

- 상단: 현재 마스코트와 단계명
- 중단: 현재 XP, 다음 임계값, 진행바
- 하단: 12단계 가로 로드맵과 선택한 단계 상세

도감은 2열 그리드다. 셀에는 실제 단계 미리보기, 단계 번호·이름, 잠금 상태만 둔다. 선택 상세에서 임계값, 이야기, 에셋 크레딧이 아닌 사용자용 보상을 보여 준다. 도감 총수와 접근성 값은 정책 count에서 가져오며 “14”를 하드코딩하지 않는다.

## 11. 에셋과 라이선스

### 11.1 재사용

- Assets.xcassets의 Squirrel_Growth_Level_1…7
- Resources/MascotRig/level_01…level_07
- ForestScene/Home의 기존 레이어
- art 디렉터리의 첫 제작 출처 메모
- Apache 2.0 Lottie 의존성과 기존 THIRD_PARTY_NOTICES

1–7 에셋 이름과 연결을 바꾸지 않는다.

### 11.2 8–12 제작

8–12는 기존 7단계 몸체 비율·얼굴·선 두께를 기준으로 다음 레이어를 첫 제작한다.

- 투명 액세서리
- 단계별 숲 배경 또는 조명
- 단계 프레임·배지
- 정적 fallback PNG와 필요한 경우 같은 구성의 Lottie

같은 7단계 그림 위에 SF Symbol 번호만 붙인 상태를 최종 에셋으로 인정하지 않는다. 에셋이 늦으면 기능 플래그로 미완성 단계를 숨기는 대신, 단계명·XP는 유지하고 “그림 준비 중” 중립 대체를 사용한다.

### 11.3 음식 아이콘

초기 카테고리는 12–24개 이내로 제한한다. 우선순위는 다음과 같다.

1. 팀이 직접 제작하거나 생성 후 권리를 보유한 일관된 아이콘
2. MIT, Apache-2.0, BSD, CC0 또는 상업 사용·수정·재배포가 명확한 세트
3. 에셋이 없을 때 SF Symbols 카테고리 fallback

검색 결과 이미지, 출처 불명 PNG, 저작자 표시 조건을 충족할 수 없는 파일은 포함하지 않는다. 새 파일마다 asset-manifest에 원본명, 제작자/생성 경로, 라이선스, 원본 URL 또는 내부 출처, 수정 여부를 기록하고 필요한 고지를 THIRD_PARTY_NOTICES에 반영한다.

## 12. 접근성

- 모든 주요 동작은 48×48pt 이상이다.
- Dynamic Type에서 레이아웃이 커지고, 월간 셀은 글자를 축소하는 대신 정보를 단계적으로 생략한다.
- VoiceOver 순서는 날짜 → 데이터 상태 → 메뉴 → 알레르기 → 영양 → 기록 CTA다.
- 음식·마스코트 장식 이미지는 숨기고, 의미가 있는 단계 이미지는 “8단계 별빛 셰프, 잠금 해제됨”처럼 읽는다.
- 알레르기, 잠금, 완료는 텍스트·아이콘·모양을 함께 사용한다.
- Reduce Motion에서는 레벨업·배지 애니메이션을 최종 정적 프레임과 햅틱 없음으로 대체한다.
- Increase Contrast에서 의미 색의 대비를 재검증한다.
- 기기 글꼴 최대 크기와 iPhone SE 폭에서 상태 그리드·달력·도감이 잘리지 않는다.
- 앱 스토어 접근성 선언은 수동·자동 검증이 끝난 항목만 제출한다.

## 13. 오류와 오프라인

- 앱 시작 시 성장 정책 로드 실패는 마지막 내장 기본 12단계 정책으로 복구하고 오류를 진단 로그에 남긴다.
- 날짜 상세는 캐시를 우선 표시하고 갱신 실패 때문에 캐시를 지우지 않는다.
- 급식 없음과 네트워크 실패를 같은 빈 화면으로 표현하지 않는다.
- 영양 규칙 로드 실패는 기록 자체를 막지 않는다. 일반 교육 문구로 저장하고 snapshot에 fallback ruleVersion을 기록한다.
- 에셋 실패는 데이터 저장과 XP 지급에 영향을 주지 않는다.
- Core Data 모델 마이그레이션 실패 시 스토어를 삭제·재생성하지 않는다.

로그에는 프로필 이름, 학교 상세, 메뉴 기록 전문, 보호자 링크, 비밀값을 넣지 않는다. 필요한 경우 익명화한 dateKey 상태와 규칙 버전만 남긴다.

## 14. 테스트 전략

### 14.1 성장 단위 테스트

- 정책 count가 12인지
- 임계값이 정확히 0, 80, 180, 320, 500, 720, 1000, 1300, 1650, 2050, 2500, 3000인지
- 공개 1–7 이름이 변경되지 않았는지
- 경계값 직전·정확히·직후 단계 계산
- 3000과 4850 이상의 XP가 12단계이며 XP가 유지되는지
- 정책 title과 asset key 중복·누락 실패

### 14.2 마이그레이션 테스트

고정 fixture로 다음 경로를 모두 실행한다.

- 공개 1.1 신규 업그레이드
- 이미 완료된 Rebuild v1 store가 `alreadyCompleted`로 유지되는 경로
- 과거 14단계 후보에서 높은 XP를 쌓은 QA fixture의 12단계 해석
- optional 필드가 없는 오래된 Codable payload와 malformed/partial `growth-stage-state-v2`
- 사진·보호자 링크·공유 상태가 있는 payload
- 배지와 skin-7 선택이 있는 payload

각 fixture에서 XP 합계, record/photo/link 식별자, badge 문자열, legacy `currentSkinId`, v2 최고 해금·선택 값, 원본 UserDefaults 바이트, v1 migration state version/digest를 비교한다. Core Data model attribute 집합이 공개 v1과 같고 v2 backfill이 호출되지 않는 것도 고정한다.

### 14.3 달력·상세 테스트

- 주간이 월요일부터 일요일 7일인지
- 월말·연말·윤년·Asia/Seoul 자정 경계
- 주간·월간 선택 dateKey와 상세 요청 dateKey 일치
- 캐시, 갱신, 최신, 없음, 실패별 UI
- 데이터가 없을 때 오늘/첫 급식 fallback이 발생하지 않음
- 좁은 폭과 큰 글자에서 날짜 선택 가능

### 14.4 영양·기록 테스트

- 알레르기 번호와 공백을 제거해도 원문이 보존되는지
- 구조화 nutrient가 키워드 규칙보다 우선하는지
- exact/keyword/fallback 결과
- individual menu sidecar snapshot에 정량값이 생성되지 않는지
- 어려웠어요 대체 메뉴가 같은 급식·알레르기 안전 조건을 지키는지
- 여섯 상태가 모두 노출되는지
- 알레르기 위험 상태가 UI와 유스케이스에서 동일하게 허용/차단되는지
- 상태 수정 뒤 활성 기록 1개, XP 이벤트 1개인지
- 이전 기록의 사진과 sourceRecordID가 유지되는지

### 14.5 영양 sidecar·Core Data v1 회귀

- `NutrientImpactSidecar` 설치/read-back 성공 뒤에만 기존 record/event가 저장되는지
- sidecar 설치 실패·Core Data 저장 실패·재시작 경계에서 record/event와 sidecar가 서로 거짓으로 결합되지 않는지
- 상태 변경은 immutable 새 revision 파일을 만들고 이전 파일을 덮어쓰지 않는지
- 현재 record의 recordID/date/normalizedMenuName/status/updatedAt과 정확히 맞는 sidecar만 당시 안내로 읽는지
- 손상 JSON, fingerprint 불일치, path traversal, 금지 문구·정량값은 무시하고 “현재 기준 안내”로 내리는지
- 공개 v1 `RebuildManagedModel` attribute 집합·optional 집합·unique constraint와 `RebuildMigrationState` version/digest가 그대로인지
- 새 optional Core Data column, model migration, v2 migration backfill이 존재하지 않는지

### 14.6 UI·접근성·시각 회귀

- TodayForest, MealDayDetail, MealRecording, Growth, Collection 스냅샷
- 일반/최대 Dynamic Type, light/dark가 지원 범위라면 양쪽
- VoiceOver 라벨·순서
- Reduce Motion
- iPhone SE와 최신 6.1/6.7인치 기기
- 12단계 각 에셋과 fallback
- 공개용 네 장 스크린샷에 디버그·개인정보·임시 문구가 없는지

### 14.7 출시 검증

- Debug와 Release 빌드
- Release에서 실제 root가 기대한 Rebuild인지
- MARKETING_VERSION, CURRENT_PROJECT_VERSION, App Store metadata 일치
- bundle id com.h19h29.naymnaymlevelup 유지
- 라이선스 manifest와 THIRD_PARTY_NOTICES 확인
- 비행기 모드 캐시·기록·재실행 확인
- 설치된 1.1 위에 업데이트하는 실기기 테스트

## 15. 구현 순서

1. 성장 정책, read-only legacy rights union, bounded `growth-stage-state-v2`와 Core Data v1/migration-state 불변 테스트를 먼저 추가한다.
2. 12단계 정책·성장 화면·도감을 연결하고 8–12의 검증된 원화 또는 중립 fallback을 표시한다.
3. 날짜 계약을 월–일로 보강하고 공통 `MealDayDetailView`를 연결한다.
4. `NutritionRuleEngine`을 최소 확장하고 `NutrientImpactSnapshot`·immutable sidecar·정확한 record revision을 테스트한다.
5. `MealSafetyPolicy`와 활성 기록 단일화를 적용하고 상태 선택→영양 확인→확정→저장 흐름을 연결한다.
6. 의미 색·음식 아이콘·접근성 레이아웃을 연결한다.
7. sidecar·v1 Core Data schema·v1 migration state·오프라인·스크린샷·스토어 제출 자산을 검증한다.

각 단계는 기존 테스트를 유지하며 다음 단계로 이동한다. 에셋 제작 지연이 데이터·달력·안전 로직 검증을 막지 않도록 asset key와 fallback 계약을 먼저 고정한다.

## 16. 비목표

- 공개 1–7 임계값 또는 기존 XP 재산정
- 메뉴별 g, mg, kcal 추정이나 의료·영양 진단
- 새 계정 서버, 보상 상점, 소셜 피드
- legacy와 Rebuild의 전면 통합 또는 재작성
- 대형 테마 패키지, 범용 라우터, 새 네트워크 추상화
- 모든 급식 이름을 완벽히 분류하는 머신러닝 모델
- Figma 14단계 보드의 그대로 구현
- 보호자용 새 기록 이력 화면
- 릴리스 버전·프로젝트 설정 변경

## 17. 완료 정의

다음이 모두 참일 때 성장·급식 경험 개선 v2 구현을 완료로 판정한다.

- 정책·화면·테스트가 정확히 12단계다.
- 공개 1–7과 모든 사용자 데이터의 마이그레이션 불변 검증이 통과한다.
- 8–12가 서로 구분되는 배포 가능 에셋 또는 명시적 중립 fallback을 갖는다.
- 오늘·주간·월간이 같은 상세를 열며 선택 날짜를 바꾸지 않는다.
- 여섯 상태, 대표 영양 피드백, 알레르기 안전, 단일 활성 기록이 통합된다.
- 접근성·오프라인·기기 폭·Release 빌드 테스트가 통과한다.
- 메타데이터와 공개용 네 장의 실제 스크린샷이 구현과 일치한다.
- 임시 문구, 출처 불명 에셋, 하드코딩된 14단계 문구가 없다.
