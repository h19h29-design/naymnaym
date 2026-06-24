# TestFlight / App Store 준비 체크리스트

## 현재 검증 완료
- `Config.xcconfig`는 Git 제외 대상이다.
- NEIS API 키는 코드나 로그에 노출하지 않는다.
- 실제 학교 선택 상태에서 샘플 급식 자동 fallback을 하지 않는다.
- `PrivacyInfo.xcprivacy`에 UserDefaults required reason API 사유와 선택 부모 공유용 수집 데이터 타입을 선언했다.
- iOS Simulator Debug 빌드, 설치, 실행과 XCTest 55개가 통과한다.
- Release/generic iOS archive와 App Store Connect remote-signed export가 통과한다.
- TestFlight build 1.0 (12) signed IPA가 생성됐다.
- build 12 export summary에서 TestFlight beta entitlement와 App Store 프로비저닝 서명을 확인했다.
- build 12 CLI 업로드가 성공했고, App Store Connect 처리 상태 확인이 남아 있다.
- 요구사항별 감사 결과는 `docs/RELEASE_READINESS_AUDIT.md`에 정리했다.

## App Store Connect에서 필요한 값
- 앱 이름: 냠냠레벨업
- 부제: 한 입 도전 급식 코칭
- 카테고리: 교육 또는 건강 및 피트니스 중 최종 선택
- 가격: 무료
- 연령 등급: 알레르기/건강 진단 표현 없음 기준으로 입력
- 개인정보 처리방침 URL: `https://h19h29-design.github.io/naymnaym/privacy.html`
- 지원 URL: `https://h19h29-design.github.io/naymnaym/support.html`
- 데이터 안전 안내 URL: `https://h19h29-design.github.io/naymnaym/data-safety.html`

## App Privacy 입력 초안
- 회원가입 없음
- 이름, 이메일, 전화번호 수집 없음
- 위치정보 수집 없음
- 광고 없음
- 인앱결제 없음
- 별명, 학교, 알레르기, 먹은 정도, 사진 메타데이터는 기본적으로 기기 내부 저장
- 부모 연동 시 사용자가 선택한 기록과 사진만 공유
- 앱 안에서는 기록 공유와 사진 공유를 별도 선택으로 분리
- 급식 조회를 위해 선택 학교 코드와 날짜가 NEIS 공공데이터 API 요청에 사용될 수 있음

## 심사용 안내문 초안
냠냠레벨업은 NEIS 공공데이터 기반 무료 급식 식습관 코칭 앱입니다. 회원가입 없이 별명과 학교를 선택해 사용합니다. 샘플 데이터는 사용자가 체험 모드를 직접 선택한 경우에만 표시되며, 실제 학교 급식 조회 실패 시 샘플로 대체하지 않습니다. 알레르기 안내는 안전을 보장하지 않고 학교 안내와 보호자 판단이 우선임을 앱 안에 명시했습니다.

## 스크린샷 체크리스트
- 6.9형 업로드 후보: `docs/app-store-screenshots/iphone-6-9-upload/`
- 규격 검증: `1320 x 2868`, JPG, alpha 없음
- 오늘 급식: `01-today-no-meal.jpg`
- 실제 월간 NEIS 식단: `02-monthly-calendar-live.jpg`
- 레벨/캐릭터: `03-level-character.jpg`
- 보호자 요약: `04-parent-summary.jpg`
- 설정/개인정보/지원 접근: `05-settings-privacy-support.jpg`
- 앱 내 개인정보 처리방침: `06-privacy-policy.jpg`
- 앱 내 지원 안내: `07-support-guide.jpg`
- 보조 6.3형 원본: `docs/app-store-screenshots/*.png`
- 세부 설명: `docs/APP_STORE_SCREENSHOTS.md`

## TestFlight 내부 테스트
- 실제 학교 검색 결과 확인
- 급식 있는 평일 화면 확인
- 급식 없는 날 `noMeal` 안내 확인
- API 키 없음 상태 `missingAPIKey` 안내 확인
- 체험 모드에서만 샘플 표시 확인
- 알레르기 메뉴 한 입 도전 잠금 확인
- 사진 선택/촬영/삭제 확인
- 부모 연결 초대 코드 화면 확인
- 아이 폰 설정 > 보호자 연결에서 초대 코드 생성 확인
- 부모 모드 > 아이 추가에서 초대 코드 연결 확인
- 부모 모드에서 여러 아이 기록이 섞이지 않는지 확인
- 설정 > 개인정보 처리방침 보기 확인
- 설정 > 지원 안내 보기 확인

## 제출 전 남은 계정 작업
- App Store Connect에서 build 12 처리 완료 확인
- build 12를 내부 테스트 그룹에 연결
- build 12를 외부 테스트 그룹 `패밀리`에 연결
- 외부 테스트 그룹 공개 링크가 build 12를 가리키는지 확인
- 외부 테스트 심사 제출
- CloudKit Dashboard에서 public database schema 배포 확인
- CloudKit Dashboard에서 `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto` record type 확인
- CloudKit Dashboard에서 queryable index 구성:
  - `ParentLink.inviteCode`
  - `SharedMealRecord.childLinkId`
  - `SharedChallengeRecord.childLinkId`
  - `SharedMealPhoto.childLinkId`
- `createdAt` 최신순 정렬은 앱 내부에서 처리하므로 CloudKit sortable index는 필요 없음
- CloudKit public database 권한 확인:
  - 앱 사용자가 `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto`를 생성/수정할 수 있어야 함
  - 초대 코드 조회는 정확한 `inviteCode` 조건으로만 동작하는지 확인
- 개인정보 처리방침/지원/데이터 안전 URL GitHub Pages 공개 확인 완료
- App Privacy 답변에서 부모 공유 시 CloudKit에 저장될 수 있는 사용자 콘텐츠, 사진/동영상, 건강 정보, 사용자 ID를 앱 기능 제공 목적과 연결된 데이터로 입력

## 공식 제출 참고
- Apple App Store Connect 도움말에 따르면 iOS 앱의 개인정보 처리방침 URL은 필수 입력 항목이다.
- Apple App Privacy Details 안내에 따르면 앱과 제3자 파트너가 수집하는 데이터 유형과 사용 목적을 App Store Connect에 입력해야 한다.
- Apple App Review Guidelines는 앱 안에서도 개인정보 처리방침에 쉽게 접근할 수 있어야 한다고 안내한다.
- Apple required reason API 안내에 따라 UserDefaults 사용은 Privacy Manifest에 사유를 선언해야 한다.
- Apple App Store Connect screenshot specifications에 따르면 iPhone 6.9형 portrait 허용 크기에는 `1320 x 2868`이 포함된다.

공식 문서:
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
