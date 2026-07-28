# 급식레벨업 Google Play Console 입력 초안

이 문서는 Android 정식 출시 전 Play Console 입력을 위한 초안입니다. 최종 제출 전 실제 빌드, Supabase 부모 연결 서버 설정, 개인정보 처리방침 URL을 다시 확인합니다.

## 기본 정보

- 앱 이름: 급식레벨업
- 패키지명: `com.h19h29.naymnaymlevelup`
- 버전: `1.1`
- versionCode: `11`
- 카테고리: 교육
- 가격: 무료
- 광고 포함: 아니요
- 인앱 상품/결제: 없음
- 개인정보 처리방침 URL: `https://nyam.h19h19.com/privacy.html`
- 지원 URL: `https://nyam.h19h19.com/support.html`
- 데이터 안전 안내 URL: `https://nyam.h19h19.com/data-safety.html`
- Android 테스트 앱 권한: 인터넷 권한만 사용. 알림, 위치, 연락처, 카메라, 사진 권한은 요청하지 않음

## 앱 액세스

- 로그인 필요: 아니요
- 테스트 계정 필요: 아니요
- 첫 실행에서 `아이로 시작`을 선택하고 별명과 학교를 등록하면 주요 기능 확인 가능
- 보호자 연결은 초대 코드가 필요하지만, 아이 모드의 학교 검색과 급식 조회에는 로그인이나 테스트 계정이 필요하지 않음

## Data Safety 입력 초안

- 데이터가 제3자와 공유됨: 제한적으로 예
  - NEIS 공공데이터 API에 학교 코드와 조회 날짜가 요청될 수 있음
  - 부모 공유를 켠 기록은 Supabase 부모 연결 서버에 저장될 수 있음
- 수집 데이터:
  - Health and fitness: 알레르기 선택값, 식사 기록, 먹은 정도
  - User-generated content: 한 입 도전 기록, 어려운 이유, 먹은 정도 기록
  - App info and performance / Diagnostics: 앱 자체 분석 SDK 없음
  - Photos and videos: 수집 안 함. Android 테스트 앱은 사진 업로드 기능을 포함하지 않고, iOS 사진도 부모 공유/서버 동기화 대상에서 제외
  - Personal info / Contact info: 수집 안 함
  - Location / Contacts / Financial info: 수집 안 함
- 데이터 사용 목적:
  - App functionality
  - Safety/allergy guidance display
  - Parent-child sharing after explicit invite connection
- 광고 또는 추적 목적 사용: 아니요
- 데이터 삭제:
  - 앱의 `개인정보 · 지원 · 데이터 관리 > 데이터 관리`에서 기기 내부 데이터 삭제 가능
  - 부모 서버 공유 데이터는 지원 요청 또는 향후 계정/연결 삭제 흐름에서 처리

## 콘텐츠 등급/타겟 대상

- 폭력, 성적 콘텐츠, 도박, 사용자 공개 피드, 자유 채팅 없음
- 영양/알레르기 안내는 교육용 참고 정보이며 진단/치료/안전 보장 아님
- Kids Category/Designed for Families는 우선 선택하지 않고 일반 교육 앱으로 준비
- 타겟 연령은 앱 소유자가 Play Console 설문에서 최종 확인

## 심사용 설명

급식레벨업은 NEIS 공공데이터 기반 무료 급식 식습관 코칭 앱입니다. 회원가입 없이 `아이로 시작`을 선택하고 별명과 학교를 등록하면 사용할 수 있습니다. 실제 학교 API 실패나 급식 없는 날에는 샘플 식단으로 대체하지 않습니다. 알레르기 번호가 있는 메뉴는 한 입 도전 버튼을 잠그고 학교 안내와 보호자 판단이 우선임을 안내합니다. 부모 공유는 초대 코드로 연결한 뒤 먹은 정도, 한 입 도전 기록, 알레르기 주의만 사용합니다. Android 앱은 현재 알림, 위치, 연락처, 카메라 또는 사진 권한을 요청하지 않습니다.

## 휴대전화 스크린샷

- `phone-screenshots/01-today-forest.png`: 오늘 급식과 숲속 캐릭터
- `phone-screenshots/02-meal-recording.png`: 메뉴별 먹은 정도와 한 입 도전 기록
- `phone-screenshots/03-growth.png`: XP와 다음 레벨 성장 현황
- `phone-screenshots/04-growth-collection.png`: 해금한 캐릭터와 성장 도감

모든 파일은 Android 에뮬레이터의 실제 1.1 화면을 1080 × 1920 크기로 촬영한 이미지입니다.
