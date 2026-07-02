# 냠냠레벨업 App Privacy 답변 초안

이 문서는 App Store Connect의 App Privacy 입력을 위한 보수적 초안입니다. 최종 제출 전 앱 소유자가 실제 배포 빌드, Supabase 부모 연결 서버 설정, 개인정보 처리방침 URL과 함께 확인해야 합니다.

## 추적

- 사용자를 추적합니까? 아니요
- 제3자 광고 목적으로 데이터를 사용합니까? 아니요
- 광고 식별자 또는 추적 SDK를 사용합니까? 아니요

## 수집하지 않는 것으로 보이는 데이터

검토 기준: 현재 코드에 회원가입, 광고 SDK, 분석 SDK, 위치 권한, 연락처 권한, 결제 기능이 없음.

- Contact Info: 수집 안 함
- Location: 수집 안 함
- Contacts: 수집 안 함
- Purchases: 수집 안 함
- Browsing History: 수집 안 함
- Search History: 수집 안 함
- Usage Data: 자체 분석 SDK 없음

## 최종 확인 데이터

아래 항목은 기능상 사용자 입력 또는 선택 공유가 있으므로 “Data Not Collected”로 단정하지 말고 App Store Connect에서 보수적으로 확인해야 합니다.

## App Store Connect 입력 매트릭스

현재 코드와 Privacy Manifest 기준의 보수적 입력안입니다. 앱 소유자는 제출 직전 실제 부모 연결 서버 설정과 화면 문구를 함께 확인해야 합니다.

| App Privacy 항목 | 현재 입력안 | 목적 | 사용자 연결 | 추적 | 근거 |
| --- | --- | --- | --- | --- | --- |
| Contact Info | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 회원가입, 이메일, 전화번호 입력 없음 |
| Location | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 위치 권한과 CoreLocation 사용 없음 |
| Contacts | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 연락처 권한 사용 없음 |
| Purchases | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 인앱결제/StoreKit 사용 없음 |
| Usage Data | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 자체 분석 SDK 없음 |
| Other User Content | 수집함 | App Functionality | 예 | 아니요 | 먹은 정도, 한 입 도전 기록, 어려운 이유는 부모 공유 시 서버 저장 가능 |
| Photos or Videos | 수집 안 함 | 해당 없음 | 해당 없음 | 아니요 | 급식판 사진은 기기 내부에만 저장하고 서버 부모 동기화나 부모 모드로 업로드하지 않음 |
| Health and Fitness | 수집함 | App Functionality | 예 | 아니요 | 알레르기 선택값과 식사 기록이 건강 관련 정보로 해석될 수 있음 |
| User ID | 수집함 | App Functionality | 예 | 아니요 | 부모 연결용 `childLinkId`와 초대 코드 사용 |

Tracking은 `아니요`로 입력한다. 광고 SDK, 분석 SDK, 제3자 광고, 데이터 브로커 공유 목적은 현재 코드에 없다.

### User Content

- 대상: 먹은 정도 기록, 한 입 도전 기록, 어려운 이유
- 기본 저장: 기기 내부
- 공유 가능: 부모 공유를 켠 기록만 서버에 저장될 수 있음
- 목적: App Functionality
- Linked to User: 부모 연결을 사용하는 경우 `childLinkId`와 연결될 수 있음
- Tracking: 아니요

### Photos or Videos

- 대상: 사용자가 선택하거나 촬영한 급식판 사진
- 기본 저장: 기기 내부
- 서버 전송: 없음
- 부모 공유: 없음
- App Store Connect 입력: 수집 안 함
- Tracking: 아니요

### Health and Fitness

- 대상: 알레르기 선택값, 식사 기록, 어려운 이유가 건강 관련 정보로 해석될 수 있음
- 목적: 알레르기 주의 표시, 식습관 기록, 부모 공유 기능
- Linked to User: 부모 공유를 사용하는 경우 연결될 수 있음
- Tracking: 아니요
- 주의: 앱은 진단, 치료, 안전 보장을 하지 않음

### Identifiers

- 대상: 부모 연결용 초대 코드, `childLinkId`
- 목적: 부모-자녀 연결과 다자녀 기록 분리
- Linked to User: 예
- Tracking: 아니요

### Other Data

- 대상: 선택 학교 코드, 교육청 코드, 조회 날짜
- 목적: NEIS 학교기본정보/급식식단정보 API 조회
- Linked to User: 앱 내부 프로필과 함께 저장될 수 있음
- Tracking: 아니요

## Privacy Manifest 기준

현재 `NaymNaymLevelUp/PrivacyInfo.xcprivacy`는 다음 방향으로 선언되어 있습니다.

- UserDefaults required reason API: 앱 설정/기록 저장
- 부모 공유 선택 시 사용자 콘텐츠/건강 정보/사용자 ID 가능성
- Tracking: false

## 최종 제출 전 확인

- Supabase `parent-sync` Edge Function과 `nyam_parent_*` 테이블에 실제 저장되는 필드 확인
- 부모 공유를 끈 상태에서 서버 전송이 없는지 확인
- 사진 원본이 서버 부모 동기화로 전송되지 않는지 확인
- 개인정보 처리방침 URL 공개 확인: `https://h19h29-design.github.io/naymnaym/privacy.html`
- App Privacy 답변과 `PrivacyInfo.xcprivacy`가 서로 충돌하지 않는지 확인
