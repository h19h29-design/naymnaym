# 급식레벨업 1.2 App Store Connect / CloudKit 콘솔 런북

이 문서는 앱 소유자가 로컬 검증 이후 콘솔에서 직접 확인할 항목을 정리한다. 현재 후보 검증은 업로드 없는 모드이며, App Store Connect 업로드나 App Review 제출을 수행하지 않는다.

## 현재 배포 후보

- 앱 이름: 급식레벨업
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 버전: `1.2`
- 빌드: `34`
- 가격: 무료
- 카테고리: 교육
- 개인정보 처리방침 URL: `https://nyam.h19h19.com/privacy.html`
- 지원 URL: `https://nyam.h19h19.com/support.html`
- 데이터 안전 안내 URL: `https://nyam.h19h19.com/data-safety.html`
- 현재 상태: 로컬 Debug/Release 및 메타데이터 검증 후보, 업로드 안 함

## 1.2 사용자 변경 사항

- 캐릭터 성장 단계가 12단계로 늘어났어요.
- 일간·주간·월간 급식표에서 선택한 날짜의 메뉴·알레르기·영양 상세를 확인할 수 있어요.
- 메뉴별 대표 영양소를 부담 없는 교육용 안내로 확인할 수 있어요.
- 음식 아이콘과 화면 디자인을 더 알아보기 쉽게 개선했어요.

## 업로드 없는 로컬 검증

다음 명령은 실제 Xcode 프로젝트, 로컬 Debug/Release 산출물, 메타데이터, entitlement 원본, Privacy Manifest, 라이선스 및 공개 지원 URL을 확인한다. App Store Connect API나 업로드 명령을 호출하지 않는다.

```sh
EXPECTED_MARKETING_VERSION=1.2 EXPECTED_BUILD_NUMBER=34 RELEASE_UPLOAD_REQUIRED=0 bash scripts/verify-release-readiness.sh
```

`RELEASE_UPLOAD_REQUIRED=0`에서는 signed archive, export IPA, 업로드 로그를 요구하지 않는다. 별도로 승인된 배포 작업에서 해당 산출물과 업로드 증거가 이미 준비된 경우에만 `RELEASE_UPLOAD_REQUIRED=1` 검증을 사용한다.

## App Store Connect 입력 기준

- 앱 이름: `급식레벨업`
- 부제: `편식을 한 입 도전으로 바꾸는 급식 코칭 앱`
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 버전/빌드: `1.2` / `34`
- 카테고리: `교육`
- 가격: `무료`
- 테스트 계정: 필요 없음
- 암호화: 비면제 암호화 사용 안 함, `ITSAppUsesNonExemptEncryption = false`

키워드:

급식, 학교급식, 식단, 한입도전, 편식, 식습관, 영양교육, 알레르기, 초등학생, 중학생, 고등학생, 부모

샘플 급식은 사용자가 체험 모드를 명시적으로 선택한 경우에만 표시한다. 실제 학교 조회 실패, API 키 없음, 급식 없는 날에는 샘플로 자동 대체하지 않는다. 대표 영양소와 알레르기 안내는 교육용 참고 정보이며 학교 안내와 보호자 판단이 항상 우선이다.

## App Privacy 답변 기준

최종 답변은 앱 소유자가 `release/AppStoreMetadata/app-privacy-draft.md`와 실제 후보를 대조해 확정한다.

- Tracking: 아니요
- Third-party advertising: 아니요
- Analytics SDK: 없음
- Contact Info, Location, Contacts, Purchases: 수집 안 함
- Other User Content: 사용자가 부모 공유를 켠 식사 기록만 앱 기능 제공 목적으로 서버 저장 가능
- Photos or Videos: 수집 안 함. 급식판 사진은 기기 내부에만 저장하고 부모 모드나 서버로 업로드하지 않음
- Health and Fitness: 알레르기 선택값과 식사 기록을 앱 기능 제공 목적 데이터로 보수적으로 신고
- User ID: 부모 연결용 초대 코드와 `childLinkId`를 앱 기능 제공 목적으로 신고
- 광고, 인앱결제, 분석 SDK, 추적 SDK: 없음

## 부모 연결 운영 설정

부모 연결은 Supabase Edge Function `parent-sync`가 주 경로다. CloudKit 계약은 레거시 호환 범위로 유지하고 사진 공유 record type은 사용하지 않는다.

Supabase 확인 항목:

- Edge Function: `parent-sync`
- Tables: `nyam_parent_links`, `nyam_parent_meal_records`, `nyam_parent_challenge_records`, `nyam_parent_devices`
- Public Data API 직접 접근: 사용하지 않음
- 사진 원본/사진 ID: 서버 저장하지 않음
- 부모 알림: APNs device token을 등록하고 사용자가 공유한 기록에 대해서만 발송

CloudKit 확인 항목:

- Container: `iCloud.com.h19h29.naymnaymlevelup`
- Database: Public Database
- Record types: `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`
- Queryable indexes: `ParentLink.inviteCode`, `SharedMealRecord.childLinkId`, `SharedChallengeRecord.childLinkId`
- `SharedMealPhoto` record type을 요구하지 않음

구조화된 기준은 `release/CloudKit/schema-contract.json`이며, 콘솔과 다르면 JSON 계약과 앱 코드/테스트를 먼저 대조한다.

## 운영 스모크 테스트

1. 아이 모드에서 보호자 연결 초대 코드를 생성한다.
2. 부모 모드에서 같은 초대 코드로 아이를 연결한다.
3. 공유 권한별로 식사 기록과 한 입 도전 기록이 분리되는지 확인한다.
4. 공유 권한을 끈 알레르기 정보가 서버 응답에서 제외되는지 확인한다.
5. 급식판 사진 원본과 사진 ID가 부모 화면, Supabase, CloudKit 경로에 나타나지 않는지 확인한다.
6. 여러 아이의 기록이 서로 섞이지 않는지 확인한다.
7. APNs가 구성된 환경에서만 부모 알림 수신을 확인한다.

## 멈춰야 하는 지점

다음 작업은 앱 소유자의 명시적 승인과 계정 접근이 필요하다.

- Apple ID 로그인 또는 2FA
- Apple Developer Program 계약이나 법적 동의
- 배포 인증서 또는 프로비저닝 권한 사용
- App Privacy 및 연령 등급 최종 제출
- signed archive/export 생성
- App Store Connect 또는 TestFlight 업로드
- TestFlight 그룹 연결
- App Review `Submit for Review`

인증정보, API 키, 토큰, 암호, private key 값은 문서·명령행·로그·Git에 남기지 않는다.
