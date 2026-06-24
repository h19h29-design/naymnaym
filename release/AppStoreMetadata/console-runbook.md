# App Store Connect / CloudKit 콘솔 런북

이 문서는 build 14 업로드 이후 앱 소유자가 App Store Connect와 CloudKit Dashboard에서 직접 확인해야 하는 항목을 코드 기준으로 정리한 실행 순서다. build 14는 업로드 자체는 성공했지만 실제 signed IPA에 iCloud/CloudKit entitlement가 없어 최종 외부 테스트 또는 출시 후보로 연결하지 않는다.

## 현재 배포 후보

- 앱 이름: 냠냠레벨업
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 버전: `1.0`
- 최신 업로드 빌드: `14`
- 가격: 무료
- 카테고리: 교육
- 개인정보 처리방침 URL: `https://h19h29-design.github.io/naymnaym/privacy.html`
- 지원 URL: `https://h19h29-design.github.io/naymnaym/support.html`
- 데이터 안전 안내 URL: `https://h19h29-design.github.io/naymnaym/data-safety.html`
- TestFlight 업로드 상태: build 14 CLI 업로드 성공. 단, 실제 IPA signed entitlements에 iCloud/CloudKit이 없어 build 15 이상 재서명/재업로드 전까지 release hold.

## 현재 release hold

build 14 IPA를 직접 풀어 `codesign -d --entitlements :-`로 확인한 결과, signed app에는 `application-identifier`, `beta-reports-active`, team identifier, `get-task-allow`만 있고 iCloud/CloudKit entitlement가 없다.

진행 전 계정 소유자가 먼저 확인해야 할 항목:

1. Apple Developer에서 `com.h19h29.naymnaymlevelup` App ID에 iCloud/CloudKit capability가 켜져 있는지 확인한다.
2. iCloud container `iCloud.com.h19h29.naymnaymlevelup`가 App ID에 연결되어 있는지 확인한다.
3. App Store provisioning/remote signing export가 해당 iCloud entitlement를 포함하도록 재생성한다.
4. 로컬 Mac에서 signing keychain/certificate 접근 팝업이 뜨면 허용한다.
5. build 15 이상으로 archive/export/upload를 다시 진행한다.
6. 업로드 전 exported IPA의 signed entitlements에 아래 두 값이 실제 포함됐는지 확인한다.
   - `com.apple.developer.icloud-container-identifiers: iCloud.com.h19h29.naymnaymlevelup`
   - `com.apple.developer.icloud-services: CloudKit`

## TestFlight 공개 순서

1. App Store Connect에서 냠냠레벨업 앱으로 이동한다.
2. build 14는 CloudKit entitlement가 없으므로 내부/외부 테스트 그룹에 최종 후보로 연결하지 않는다.
3. build 15 이상에서 exported IPA signed entitlements 검증을 통과한 뒤 TestFlight 빌드 목록 처리 완료 여부를 확인한다.
4. 검증 통과 빌드를 내부 테스트 그룹에 연결한다.
5. 외부 테스트 그룹 `패밀리`를 만들거나 기존 그룹을 사용한다.
6. 검증 통과 빌드를 외부 테스트 그룹 `패밀리`에 연결한다.
7. 공개 링크가 검증 통과 빌드를 가리키는지 확인한다.
8. 외부 테스트 심사 제출 전 아래 심사용 설명을 그대로 사용한다.

심사용 설명:

냠냠레벨업은 NEIS 공공데이터 기반 무료 급식 식습관 코칭 앱입니다. 회원가입 없이 별명과 학교를 선택해 사용합니다. 샘플 데이터는 사용자가 체험 모드를 직접 선택한 경우에만 표시되며, 실제 학교 급식 조회 실패 시 샘플로 대체하지 않습니다. 알레르기 안내는 안전을 보장하지 않고 학교 안내와 보호자 판단이 우선임을 앱 안에 명시했습니다. 테스트 계정은 필요하지 않으며 첫 실행에서 체험 모드로 주요 기능을 확인할 수 있습니다.

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

최종 답변은 앱 소유자가 확인해야 한다. 현재 build 14 코드와 `PrivacyInfo.xcprivacy` 기준으로는 아래 방향이 가장 보수적이다.

- Tracking: 아니요
- Contact Info: 수집 안 함
- Location: 수집 안 함
- Contacts: 수집 안 함
- Purchases: 수집 안 함
- Usage Data: 자체 분석 SDK 없음
- User Content: 앱 기능 제공 목적, 부모 공유 선택 시 CloudKit 저장 가능
- Photos or Videos: 앱 기능 제공 목적, 사진 공유 토글이 켜진 경우만 CloudKit 저장 가능
- Health and Fitness: 알레르기 선택값과 식사 기록이 건강 관련 정보로 해석될 수 있으므로 앱 기능 제공 목적 데이터로 검토
- Identifiers: 부모 연결용 초대 코드와 `childLinkId`, 앱 기능 제공 목적
- Other Data: 선택 학교 코드, 교육청 코드, 조회 날짜. NEIS 급식 조회 목적

Tracking과 제3자 광고 목적은 모두 `아니요`로 입력한다. 광고 SDK, 분석 SDK, 인앱결제, 자체 로그인은 없다.

## CloudKit 운영 설정

Container:

- `iCloud.com.h19h29.naymnaymlevelup`
- Database: Public Database

앱이 사용하는 record type:

- `ParentLink`
- `SharedMealRecord`
- `SharedChallengeRecord`
- `SharedMealPhoto`

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

### SharedMealPhoto 필드

- `childLinkId`: String
- `photoId`: String
- `fileName`: String
- `createdAt`: Date/Time
- `photoAsset`: Asset

필수 index:

- `childLinkId`: Queryable

`createdAt` 최신순 정렬은 앱 내부에서 처리하므로 CloudKit sortable index는 필요 없다.

## CloudKit 운영 스모크 테스트

아래는 CloudKit entitlement 검증을 통과한 TestFlight build 15 이상 설치 후 실제 기기 또는 시뮬레이터에서 확인한다.

1. 아이 모드에서 보호자 연결 초대 코드를 생성한다.
2. CloudKit Public Database에 `ParentLink` record가 생성되는지 확인한다.
3. 부모 모드에서 같은 초대 코드를 입력해 아이 카드가 추가되는지 확인한다.
4. 아이 모드에서 먹은 정도 기록 공유를 켜고 기록한다.
5. CloudKit에 `SharedMealRecord`가 생성되고 `childLinkId`로 조회되는지 확인한다.
6. 한 입 도전 기록 후 `SharedChallengeRecord`가 생성되는지 확인한다.
7. 사진 공유 토글을 켠 사진만 `SharedMealPhoto`와 `photoAsset`으로 올라가는지 확인한다.
8. 사진 공유 토글을 끈 사진은 CloudKit에 올라가지 않는지 확인한다.
9. 부모 모드에서 여러 아이의 기록이 서로 섞이지 않는지 확인한다.
10. CloudKit schema를 Production에 배포한다.

## 멈춰야 하는 지점

아래 상황에서는 앱 소유자 확인 후 진행한다.

- Apple ID 로그인 또는 2FA 요구
- Apple Developer Program 결제, 계약, 법적 동의 요구
- App Privacy 답변을 사실과 다르게 입력해야 하는 상황
- 개인정보 처리방침 문구의 법률 검토가 필요한 상황
- 최종 App Review `Submit for Review` 버튼을 누르기 직전
