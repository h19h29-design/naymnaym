# 냠냠레벨업 iOS

냠냠레벨업은 학교 급식 데이터를 기반으로 아이가 안 먹는 반찬을 혼내지 않고, 먹은 정도와 한 입 도전 기록으로 식습관을 바꾸도록 돕는 무료 iPhone 앱입니다.

## 1.0 출시 범위
- 실제 NEIS 학교 검색 및 급식식단정보 조회
- 초등학생, 중학생, 고등학생, 부모 모드
- 모드별 테마와 캐릭터 성장
- 오늘 급식, 월간 급식, 칼로리/영양 안내
- 안 먹음, 한입 도전, 잘 먹음 기반 식사 기록
- 어려운 이유 선택과 한 입 도전 경험치
- 알레르기 번호 안내 및 도전 잠금
- 급식판 사진 기록과 선택적 부모 공유
- 부모 화면의 아이별 요약, 칭찬 카드, 주간 리포트
- 회원가입 없는 로컬 저장

## 데이터 정책
- 실제 학교 급식은 NEIS 학교기본정보 API와 NEIS 급식식단정보 API로 조회합니다.
- 샘플 데이터는 사용자가 명시적으로 체험 모드를 선택한 경우에만 표시합니다.
- API 키 없음, API 실패, 데이터 없음, 샘플 학교 선택 상태는 화면에서 서로 다른 상태로 표시합니다.
- 급식 화면이 실제 데이터를 샘플 배너로 대체하지 않습니다.

## 개인정보 원칙
- 회원가입 없음
- 이름, 이메일, 전화번호, 위치정보 수집 없음
- 광고 없음
- 인앱결제 없음
- 별명, 학교, 알레르기, 먹은 정도, 사진 메타데이터는 기본적으로 기기 내부에 저장
- 급식판 사진은 기본적으로 기기 내부 저장
- 부모 공유를 켠 기록과 사진만 부모 화면에서 다룸
- 공개 피드, 친구 공유, 교사용 감시 기능 없음

## CloudKit 부모 연동 구조
- 자체 서버 없이 iCloud/CloudKit 기반 부모-자녀 연결을 사용합니다.
- 아이 폰은 설정 > 보호자 연결에서 초대 코드를 만들고 `ParentLink`를 public CloudKit database에 등록합니다.
- 부모 모드는 아이 추가 화면에서 초대 코드를 조회해 여러 아이를 연결하고, 아이별 공유 기록을 따로 보여줍니다.
- 공유 대상은 먹은 정도, 한 입 도전 기록, 알레르기 주의, 사용자가 공유를 켠 사진으로 제한합니다.
- 공유 기록은 `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto` record로 저장되며, 사진은 사용자가 부모 공유를 켠 경우에만 CKAsset으로 올라갑니다.
- App Store 제출 전 iCloud capability, container, public database schema와 query index 구성이 필요합니다.
- 프로젝트에는 `NaymNaymLevelUp.entitlements`가 포함되어 있으며, Apple Developer 계정에서 `iCloud.com.h19h29.naymnaymlevelup` container를 생성/연결해야 합니다.

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
- 외부 Swift 패키지 없음

## 실행 방법
1. Xcode에서 `NaymNaymLevelUp.xcodeproj`를 엽니다.
2. iPhone 시뮬레이터를 선택합니다.
3. Build & Run을 실행합니다.

## 출시 전 체크
- 실제 학교 검색으로 officeCode, schoolCode 저장 확인
- `mealServiceDietInfo` 호출 로그 확인
- `DDISH_NM`, `CAL_INFO`, `NTR_INFO` 변환 확인
- 오늘 급식 화면의 상태 배너 확인
- 사진 권한 문구 확인
- App Privacy 정보 입력
- TestFlight 내부/외부 테스트
- App Review 제출 전 알레르기 면책 및 개인정보 처리 안내 최종 확인
