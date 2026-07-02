# 냠냠레벨업 iOS

냠냠레벨업은 학교 급식 데이터를 기반으로 아이가 안 먹는 반찬을 혼내지 않고, 먹은 정도와 한 입 도전 기록으로 식습관을 바꾸도록 돕는 무료 iPhone 앱입니다.

## 1.0 출시 범위
- 실제 NEIS 학교 검색 및 급식식단정보 조회
- 초등학생, 중학생, 고등학생, 부모 모드
- 모드별 테마와 캐릭터 성장
- 오늘 급식, 주간/월간 식단, 칼로리/영양 안내
- 안 먹음, 한 입 도전, 잘 먹음 기반 식사 기록
- 어려운 이유 선택과 한 입 도전 경험치
- 알레르기 번호 안내 및 도전 잠금
- 급식판 사진 로컬 기록
- 부모 화면의 아이별 요약, 칭찬 카드, 주간 리포트
- SNS 공유 카드와 iOS 기본 공유 시트
- 회원가입 없는 로컬 저장

## 데이터 정책
- 실제 학교 급식은 NEIS 학교기본정보 API와 NEIS 급식식단정보 API로 조회합니다.
- 샘플 데이터는 사용자가 명시적으로 체험 모드를 선택한 경우에만 표시합니다.
- API 키 없음, API 실패, 데이터 없음, 샘플 학교 선택 상태는 화면에서 서로 다른 상태로 표시합니다.
- 급식 화면이 실제 데이터를 샘플 배너로 대체하지 않습니다.
- 실제 학교를 선택한 상태에서 API 실패, 급식 없음, API 키 없음이 발생하면 샘플 급식은 표시하지 않습니다.
- 체험 모드에는 체험 모드 배지와 샘플 데이터 안내를 함께 표시합니다.

## 식단 캘린더
- 식단 탭은 주간 보기를 기본값으로 사용합니다.
- 상단 segmented picker로 주간/월간 보기를 전환합니다.
- 주간 보기에는 7일 식단, 오늘 강조, 대표 메뉴 2~3개, 데이터 상태 배지를 표시합니다.
- 월간 보기에는 메뉴를 2줄까지만 보여주고 나머지는 `+N개`로 축약합니다.
- 날짜를 누르면 상세 sheet에서 날짜, 메뉴, 칼로리, 영양정보, 알레르기 경고, 한 입 도전/먹은 정도/사진 기록 안내를 확인합니다.
- 상태 배지는 `실제 데이터`, `체험 모드`, `급식 없음`, `설정 확인`으로 구분합니다.

## 개인정보 원칙
- 회원가입 없음
- 이름, 이메일, 전화번호, 위치정보 수집 없음
- 광고 없음
- 인앱결제 없음
- 별명, 학교, 알레르기, 먹은 정도, 사진 메타데이터는 기본적으로 기기 내부에 저장
- 급식판 사진은 기본적으로 기기 내부 저장
- 부모 공유를 켠 기록만 서버에 동기화하며, 사진은 부모에게 공유하지 않고 기기 내부에 저장
- SNS 공유 카드에는 학교 상세 정보, 아이 이름, 개인 알레르기 정보, 부모 리포트 전체를 넣지 않음
- 공개 피드, 친구 공유, 교사용 감시 기능 없음

## 서버 기반 부모 연동 구조
- Supabase Edge Function `parent-sync`와 RLS가 켜진 서버 테이블로 부모-자녀 연결을 사용합니다.
- 아이폰은 설정 > 보호자 연결에서 초대 코드를 만들고 서버에 등록합니다.
- 부모 모드는 아이 추가 화면에서 초대 코드를 조회해 여러 아이를 연결하고, 아이별 공유 기록과 오늘 급식 메뉴를 따로 보여줍니다.
- 부모 급식 메뉴는 연결된 아이의 `officeCode`와 `schoolCode`로 NEIS 급식식단정보 API를 다시 조회합니다.
- 공유 대상은 먹은 정도, 한 입 도전 기록, 알레르기 주의로 제한합니다. 알레르기 주의 정보는 공유 권한이 꺼져 있으면 서버 응답에서 제외됩니다.
- 아이가 먹은 정도나 한 입 도전 결과를 올리면 부모 기기에 급식 결과 알림을 보낼 수 있습니다.
- 부모 알림은 APNs device token을 서버에 등록해 전송하며, 사진 원본은 알림이나 서버 동기화에 포함하지 않습니다.
- 아이 기기 업로드는 공유 메시지에 포함되지 않는 `inviteSecret`으로만 허용하고, 서버에는 해시만 저장합니다.
- 서버 테이블은 `nyam_parent_links`, `nyam_parent_meal_records`, `nyam_parent_challenge_records`, `nyam_parent_devices`입니다. 공개 Data API 접근은 열지 않고 Edge Function 내부 service role만 사용합니다.
- 초대 코드는 `NYAM-XXXX-XXXX-XXXX` 형식으로 표시합니다. 입력 시 공백과 하이픈은 정리하고 대문자로 맞춥니다.
- 헷갈리는 문자 `O`, `0`, `I`, `1`은 초대 코드에 사용하지 않습니다. 해당 문자가 들어간 코드는 사용자에게 경고하고 연결하지 않습니다.
- 아이 기기에서는 초대코드 생성 후 복사 버튼과 iOS 공유 시트를 사용할 수 있습니다.
- 설정의 `보호자 연동 상태 확인` 화면에서 childShareLink 존재 여부, inviteCode, 부모 childLink 수, 서버 연결 안내, 마지막 동기화 메시지/오류, 공유 권한, 공유 기록 수를 확인할 수 있습니다.
- 부모 모드에서 같은 초대 코드를 다시 입력하면 중복 연결 대신 `이미 연결된 아이` 안내를 표시합니다.
- 연결된 childLink가 없으면 부모 요약에는 가짜 아이 카드나 로컬 미리보기를 표시하지 않습니다.
- 서버 스키마 기준은 `supabase/migrations/20260702_parent_sync.sql`와 부모 알림용 `supabase/migrations/20260702_parent_notifications.sql`에 있습니다.
- Edge Function 기준은 `supabase/functions/parent-sync/index.ts`에 있습니다.

### 부모 초대코드 실패 안내
- 코드 없음: 아이 기기에서 초대 코드를 먼저 생성합니다.
- 형식 오류: `NYAM-8K3P-7M2A-C9YD`처럼 4글자씩 3묶음인지 확인합니다.
- 헷갈리는 문자 포함: `O`, `0`, `I`, `1`은 사용하지 않습니다.
- 서버 연결 실패: 네트워크 상태와 `parent-sync` Edge Function 상태를 확인합니다.
- 코드를 찾을 수 없음: 아이 기기에서 코드를 새로 확인하고 부모 기기에서 다시 입력합니다.
- 이미 연결됨: 새로고침으로 공유 기록을 다시 불러옵니다.

## 테마 시스템
- 초등학생 모드: 민트/옐로우/코랄/하늘색을 섞은 밝은 멀티컬러 톤입니다.
- 중학생 모드: 네이비/퍼플/시안 기반의 미션/게임형 톤입니다.
- 고등학생 모드: 화이트/블루/라벤더 중심의 기록 앱 톤입니다.
- 부모 모드: 코랄/인디고/크림 기반의 리포트 카드 톤입니다.
- 공통 `RoundedCard`, `PrimaryButton`, `SecondaryButton`, `BadgeView`, `AllergyChip`, `MealCard`는 초록 단색 반복을 피하도록 다채로운 semantic palette를 사용합니다.

## 알레르기 및 안전
알레르기 정보는 앱이 안전을 보장하는 기능이 아닙니다. 학교 안내와 보호자 판단이 항상 우선입니다. 선택한 알레르기와 관련된 메뉴는 한 입 도전보다 안전 확인을 먼저 하도록 표시합니다.

## API 키 설정
`Config.example.xcconfig`를 참고하여 프로젝트 루트에 `Config.xcconfig`를 만들고 `NEIS_API_KEY`를 입력합니다. 이 파일은 Git에 올리지 않습니다.

```xcconfig
NEIS_API_KEY = 발급받은_키
```

`NaymNaymLevelUp/Config/Base.xcconfig`가 루트의 `Config.xcconfig`를 optional include 하므로, 파일을 만든 뒤 다시 빌드하면 앱의 Info.plist에 `NEIS_API_KEY`가 주입됩니다.

## 개발 환경
- Xcode 26.5 확인
- SwiftUI
- iOS 16+
- XCTest
- Swift Package Manager
- lottie-ios 4.6.1

## 실행 방법
1. Xcode에서 `NaymNaymLevelUp.xcodeproj`를 엽니다.
2. iPhone 시뮬레이터를 선택합니다.
3. Build & Run을 실행합니다.

## 첫 실행 Lottie 애니메이션

첫 실행 인트로는 `lottie-ios` 기반 재생 구조를 사용합니다. SwiftUI에서는 `LottieMascotView`가 Lottie JSON을 먼저 찾고, 파일이 없거나 로딩할 수 없으면 기존 PNG 에셋 기반 fallback을 보여줍니다.

애니메이션 파일은 앱 번들 내부의 `NaymNaymLevelUp/Resources/Animations/`에 넣습니다. 앱 실행 중 외부 URL에서 Lottie 파일을 다운로드하지 않습니다.

필수 파일명:

- `mascot_intro.json`: 앱 첫 실행 시 캐릭터 등장
- `mascot_idle_loop.json`: 첫 화면 대기 반복
- `mascot_wave.json`: 캐릭터 손 흔들기
- `mascot_success.json`: 한 입 도전 성공
- `mascot_levelup.json`: 레벨업/뱃지 획득
- `mascot_allergy_warning.json`: 알레르기 주의

현재 레포에는 앱 소유 PNG 캐릭터 에셋을 움직이는 1차 Lottie JSON이 포함되어 있습니다. JSON은 `NaymNaymLevelUp/Resources/Animations/images/`의 `mascot_onboarding`, `mascot_wave_1`, `mascot_wave_2`, `mascot_jump` PNG를 참조합니다. 외부/유료 Lottie 파일을 새로 추가하거나 교체할 때는 다음 원칙을 지켜야 합니다.

- 상업적 사용 가능 라이선스가 명확한 파일만 사용
- 유료/프리미엄 또는 라이선스 불명확 파일 사용 금지
- 캐릭터가 냠냠레벨업 브랜드와 맞지 않으면 사용 금지
- 출처, 라이선스, 저작권 표기 요구사항을 `THIRD_PARTY_NOTICES.md`에 기록
- 앱 개인정보 수집, 광고, 분석 SDK를 추가하지 않음

교체 방법:

1. 위 파일명 규칙에 맞춰 Lottie JSON을 `NaymNaymLevelUp/Resources/Animations/`에 추가합니다.
2. Xcode target의 Resources에 포함되어 있는지 확인합니다.
3. `MascotAnimationState`의 상태별 `animationName`과 loop 정책을 확인합니다.
4. iPhone 16과 iPhone SE 시뮬레이터에서 첫 실행 인트로와 fallback 없는 Lottie 재생을 확인합니다.
5. 라이선스 정보를 `THIRD_PARTY_NOTICES.md`에 추가합니다.

## 출시 전 체크
- `scripts/verify-release-readiness.sh`로 plist, 버전/빌드, 아이콘, 스크린샷, 공개 URL 상태 확인
- `scripts/smoke-neis-live.sh`로 실제 NEIS 학교 검색과 급식식단정보 응답 확인
  - 기본 검증: 등촌고등학교, 2026년 6월 중식
  - 다른 학교/월 검증: `NEIS_SMOKE_SCHOOL_NAME=학교명 NEIS_SMOKE_MEAL_MONTH=YYYYMM scripts/smoke-neis-live.sh`
- 현재 릴리스 후보 상태 보고서: `release/ReleaseStatus/build-15-readiness.json`
- App Store Connect API 키가 있으면 `scripts/check-app-store-build-status.sh`로 최신 TestFlight build 처리 상태 확인
  - TestFlight 그룹 연결까지 강제 확인: `ASC_REQUIRE_BETA_GROUPS=1 ASC_EXPECTED_BETA_GROUP_NAME='패밀리' scripts/check-app-store-build-status.sh`
- 실제 학교 검색으로 officeCode, schoolCode 저장 확인
- `mealServiceDietInfo` 호출 로그 확인
- `DDISH_NM`, `CAL_INFO`, `NTR_INFO` 변환 확인
- 오늘 급식 화면의 상태 배너 확인
- 사진 권한 문구 확인
- App Privacy 정보는 `release/AppStoreMetadata/app-privacy-draft.md`의 입력 매트릭스 기준으로 App Store Connect에 입력
- 개인정보 처리방침/지원/데이터 안전 URL 공개 상태 확인 완료
- TestFlight 내부/외부 테스트
- App Review 제출 전 알레르기 면책 및 개인정보 처리 안내 최종 확인
- App Review 제출 전 Lottie JSON이 번들에 포함되어 있고, 외부 서버 다운로드나 라이선스 불명확 애니메이션이 없는지 확인
- iPhone 16과 iPhone SE에서 식단 주간 보기, 월간 보기, 상세 sheet, 부모 초대코드 입력 오류, 보호자 연동 상태 화면을 스크린샷으로 확인
- 급식판 사진이 부모 화면과 서버 동기화에 노출되지 않는지 확인
- 부모 기기 알림 권한 허용 후 아이가 급식 결과를 올리면 부모에게 알림이 가는지 확인
- 실제 학교/API 실패/급식 없음 상태에서 샘플 데이터가 자동 표시되지 않는지 확인

## App Store 제출 자료
- App Store 메타데이터 초안: `release/AppStoreMetadata/ko-KR.md`
- App Store Connect 구조 입력값: `release/AppStoreMetadata/app-store-connect-values.json`
- 이전 build 15 릴리스 상태 보고서: `release/ReleaseStatus/build-15-readiness.json`
- 사진 기록 출시 증거: `docs/PHOTO_RECORD_RELEASE_EVIDENCE.md`
- App Privacy 답변 초안: `release/AppStoreMetadata/app-privacy-draft.md`
- 제출 전 대기 메모: `release/AppStoreMetadata/submission-notes.md`
- 정적 출시 사이트: `marketing-site/dist/`, `https://h19h29-design.github.io/naymnaym/`
