# App Store Connect / CloudKit 콘솔 런북

이 문서는 build 20 후보 기준으로 앱 소유자가 App Store Connect, Supabase, CloudKit Dashboard에서 직접 확인해야 하는 항목을 코드 기준으로 정리한 실행 순서다. build 14는 업로드 자체는 성공했지만 실제 signed IPA에 iCloud/CloudKit entitlement가 없어 최종 외부 테스트 또는 출시 후보로 연결하지 않는다. build 20은 부모 급식 결과 알림과 로컬 전용 사진 정책을 포함한다.

## 현재 배포 후보

- 앱 이름: 냠냠레벨업
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 버전: `1.0`
- 최신 업로드 빌드: `20`
- 현재 제출 후보 빌드: `20`
- 가격: 무료
- 카테고리: 교육
- 개인정보 처리방침 URL: `https://h19h29-design.github.io/naymnaym/privacy.html`
- 지원 URL: `https://h19h29-design.github.io/naymnaym/support.html`
- 데이터 안전 안내 URL: `https://h19h29-design.github.io/naymnaym/data-safety.html`
- TestFlight 업로드 상태: build 20 CLI 업로드 후 App Store Connect 처리 완료와 `테스트 중` 상태를 확인한다.
- TestFlight 그룹 상태: build 20을 내부 그룹 `윈드`와 외부 그룹 `패밀리`에 연결한다.
- TestFlight 공개 링크: `https://testflight.apple.com/join/3A3rKarB`

## build 15 검증 결과

build 15 IPA를 직접 확인한 결과, embedded provisioning profile은 iCloud container `iCloud.com.h19h29.naymnaymlevelup`와 CloudKit service wildcard `*`를 허용한다. signed app entitlements에도 iCloud container와 CloudKit service가 포함되어 있다.

검증 완료 항목:

- `scripts/release-testflight-build.sh 15`: signed archive/export와 IPA entitlement 검증 통과
- `UPLOAD=1 scripts/release-testflight-build.sh 15`: TestFlight CLI upload 성공
- `scripts/verify-release-readiness.sh`: build 15 upload log, IPA entitlement, App Store icon/screenshot, 공개 URL까지 통과

### 로컬 signing keychain 접근 허용 절차

1. Mac 화면에서 숨겨진 보안 팝업이 있는지 확인한다. 문구는 보통 `codesign` 또는 Xcode가 `Apple Development: Hwayoung Lee (R6ALQZJ966)` private key 접근을 요청하는 형태다.
2. 팝업이 보이면 Mac 로그인 암호를 입력하고 `항상 허용`을 선택한다. 일회성 `허용`만 누르면 archive/export 중 같은 요청이 다시 뜰 수 있다.
3. 팝업이 보이지 않으면 Keychain Access 앱을 열고 `login` keychain의 `My Certificates`에서 `Apple Development: Hwayoung Lee (R6ALQZJ966)` 인증서와 private key가 있는지 확인한다.
4. private key 접근 제어에서 `/usr/bin/codesign`과 Xcode 접근이 차단되어 있지 않은지 확인한다. 암호나 인증서 private key 값은 문서, 로그, 채팅에 남기지 않는다.
5. 접근을 허용한 뒤 같은 터미널에서 아래 순서로 다시 실행한다.

```sh
scripts/release-testflight-build.sh 20
UPLOAD=1 scripts/release-testflight-build.sh 20
```

## TestFlight 공개 상태

1. App Store Connect에서 냠냠레벨업 앱 ID `6781586745`를 확인했다.
2. build 14는 CloudKit entitlement가 없으므로 내부/외부 테스트 그룹에 최종 후보로 연결하지 않는다.
3. build 15의 TestFlight 처리 완료와 `테스트 중` 상태를 확인했다.
4. build 15를 내부 테스트 그룹 `윈드`에 연결했다.
5. build 15를 외부 테스트 그룹 `패밀리`에 연결했다.
6. 공개 링크 `https://testflight.apple.com/join/3A3rKarB`가 활성 상태임을 확인했다.
7. 외부 TestFlight 베타 심사용 테스트 내용을 입력하고 제출했다.

심사용 설명:

냠냠레벨업은 NEIS 공공데이터 기반 무료 급식 식습관 코칭 앱입니다. 회원가입 없이 별명과 학교를 선택해 사용합니다. 샘플 데이터는 사용자가 체험 모드를 직접 선택한 경우에만 표시되며, 실제 학교 급식 조회 실패 시 샘플로 대체하지 않습니다. 알레르기 안내는 안전을 보장하지 않고 학교 안내와 보호자 판단이 우선임을 앱 안에 명시했습니다. 테스트 계정은 필요하지 않으며 첫 실행에서 체험 모드로 주요 기능을 확인할 수 있습니다.

### App Store Connect API로 build 15 상태 확인

웹 콘솔 로그인 없이 처리 상태만 확인하려면 App Store Connect API 키를 만든 뒤 아래처럼 실행한다. `.p8` 키 파일은 Git에 올리지 않는다.

```sh
ASC_KEY_ID=YOUR_KEY_ID \
ASC_ISSUER_ID=YOUR_ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_YOUR_KEY_ID.p8 \
scripts/check-app-store-build-status.sh
```

기본 조회 대상은 bundle id `com.h19h29.naymnaymlevelup`, version `1.0`, build `15`다. 최신 후보를 확인할 때는 `ASC_BUILD=20`을 지정한다.

## 남은 계정/콘솔 작업

App Store Connect 앱 목록에 업데이트된 Apple Developer Program 사용권 계약 검토 배너가 계속 보이면 계정 소유자가 계약을 검토하고 동의해야 한다. 이 항목은 TestFlight 외부 배포 완료와 별개로, 새 앱 업데이트나 최종 App Review 제출 전에 해결해야 한다.

CloudKit Dashboard에서는 `release/CloudKit/schema-contract.json` 기준으로 public database record type, queryable index, public database 권한을 최종 확인한다. App Store Connect App Privacy 답변은 `release/AppStoreMetadata/app-privacy-draft.md` 기준으로 입력하고, 최종 법적 정확성은 앱 소유자가 확인한다.

## App Store Connect 입력값

- 앱 이름: `냠냠레벨업`
- 부제: `한 입 도전 급식 코칭`
- 카테고리: `교육`
- 가격: `무료`
- 개인정보 처리방침 URL: `https://h19h29-design.github.io/naymnaym/privacy.html`
- 지원 URL: `https://h19h29-design.github.io/naymnaym/support.html`
- 저작권: `© 2026 h19h29-design. All rights reserved.`
- 테스트 계정: 필요 없음
- 암호화: 비면제 암호화 사용 안 함. `ITSAppUsesNonExemptEncryption = false`

키워드:

급식, 학교급식, 식단, 한입도전, 편식, 식습관, 영양교육, 알레르기, 초등학생, 중학생, 고등학생, 부모

## App Privacy 답변 기준

최종 답변은 앱 소유자가 확인해야 한다. 현재 build 20 업로드 후보 코드와 `PrivacyInfo.xcprivacy` 기준은 아래와 같다.

- Tracking: 아니요
- Contact Info: 수집 안 함
- Location: 수집 안 함
- Contacts: 수집 안 함
- Purchases: 수집 안 함
- Usage Data: 자체 분석 SDK 없음
- User Content: 앱 기능 제공 목적, 부모 공유 선택 시 Supabase 부모 연결 서버 저장 가능
- Photos or Videos: 수집 안 함. 급식판 사진은 기기 내부에만 저장하고 서버 부모 동기화나 부모 모드로 업로드하지 않음
- Health and Fitness: 알레르기 선택값과 식사 기록이 건강 관련 정보로 해석될 수 있으므로 앱 기능 제공 목적 데이터로 검토
- Identifiers: 부모 연결용 초대 코드와 `childLinkId`, 앱 기능 제공 목적
- Other Data: 선택 학교 코드, 교육청 코드, 조회 날짜. NEIS 급식 조회 목적

Tracking과 제3자 광고 목적은 모두 `아니요`로 입력한다. 광고 SDK, 분석 SDK, 인앱결제, 자체 로그인은 없다.

## 부모 연결 운영 설정

부모 연결은 Supabase Edge Function `parent-sync`가 주 경로다. CloudKit 계약은 레거시 호환 범위로 유지하며, 사진 공유 record type은 사용하지 않는다.

Supabase:

- Edge Function: `parent-sync`
- Tables: `nyam_parent_links`, `nyam_parent_meal_records`, `nyam_parent_challenge_records`, `nyam_parent_devices`
- Public Data API 직접 접근: 사용하지 않음
- 사진 원본/사진 ID: 서버 저장하지 않음
- 부모 알림: APNs device token을 `nyam_parent_devices`에 등록하고 아이가 공유 기록을 올릴 때 Edge Function에서 발송

구조화된 CloudKit 콘솔 설정 기준은 `release/CloudKit/schema-contract.json`이다. 아래 설명과 JSON manifest가 다르면 JSON manifest와 앱 코드/테스트를 우선 확인한다.

Container:

- `iCloud.com.h19h29.naymnaymlevelup`
- Database: Public Database

앱이 사용하는 record type:

- `ParentLink`
- `SharedMealRecord`
- `SharedChallengeRecord`

이 record type/field 계약은 `NaymNaymLevelUpTests/LocalStoreTests.swift`의 CloudKit 계약 테스트에서 고정한다.

### ParentLink 필드

- `childLinkId`: String
- `childNickname`: String
- `schoolName`: String
- `mode`: String
- `inviteCode`: String
- `shareEatingRecords`: Boolean
- `shareChallengeRecords`: Boolean
- `shareAllergyWarnings`: Boolean
- `sharePhotos`: Boolean
- `createdAt`: Date/Time

필수 index:

- `inviteCode`: Queryable

### SharedMealRecord 필드

- `mealRecordId`: String
- `childLinkId`: String
- `date`: String
- `menuName`: String
- `eatingStatus`: String
- `difficultyReasons`: String
- `allergyCodes`: String
- `photoIds`: String
- `createdAt`: Date/Time

필수 index:

- `childLinkId`: Queryable

### SharedChallengeRecord 필드

- `challengeRecordId`: String
- `childLinkId`: String
- `date`: String
- `menuName`: String
- `action`: String
- `gainedExp`: Int64
- `badgeName`: String
- `nutrients`: String
- `createdAt`: Date/Time

필수 index:

- `childLinkId`: Queryable

`createdAt` 최신순 정렬은 앱 내부에서 처리하므로 CloudKit sortable index는 필요 없다.

## CloudKit 운영 스모크 테스트

아래는 TestFlight build 20 이상 설치 후 실제 기기 또는 시뮬레이터에서 확인한다.

1. 아이 모드에서 보호자 연결 초대 코드를 생성한다.
2. `parent-sync`에 `registerInvite`가 성공하고 서버에 `nyam_parent_links` row가 생성되는지 확인한다.
3. 부모 모드에서 같은 초대 코드를 입력해 아이 카드가 추가되는지 확인한다.
4. 부모 모드에서 알림 권한을 허용하고 `registerParentDevice`가 성공하는지 확인한다.
5. 아이 모드에서 먹은 정도 기록 공유를 켜고 기록한다.
6. Supabase에 `nyam_parent_meal_records`가 생성되고 `photo_ids`가 빈 배열인지 확인한다.
7. 한 입 도전 기록 후 `nyam_parent_challenge_records`가 생성되는지 확인한다.
8. APNs 설정이 되어 있으면 부모 기기에 급식 결과 알림이 도착하는지 확인한다.
9. 사진 원본과 사진 ID가 Supabase/CloudKit 부모 공유 경로로 올라가지 않는지 확인한다.
10. 부모 모드에서 여러 아이의 기록이 서로 섞이지 않는지 확인한다.

## 멈춰야 하는 지점

아래 상황에서는 앱 소유자 확인 후 진행한다.

- Apple ID 로그인 또는 2FA 요구
- Apple Developer Program 결제, 계약, 법적 동의 요구
- App Privacy 답변을 사실과 다르게 입력해야 하는 상황
- 개인정보 처리방침 문구의 법률 검토가 필요한 상황
- 최종 App Review `Submit for Review` 버튼을 누르기 직전
