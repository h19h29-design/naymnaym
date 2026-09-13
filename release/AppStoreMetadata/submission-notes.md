# 급식레벨업 1.3 (36) 제출 메모

## 현재 후보

- 앱 이름: 급식레벨업
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 마케팅 버전: `1.3`
- 빌드: `36`
- 검증 모드: `RELEASE_UPLOAD_REQUIRED=0`

App Store Connect 업로드와 App Review 제출은 로컬 검증 및 서명 검증을 마친 승인된 배포 절차에서만 수행한다. 업로드 증거가 준비되기 전에는 `RELEASE_UPLOAD_REQUIRED=0`, 준비된 뒤에는 `RELEASE_UPLOAD_REQUIRED=1`로 검증한다.

## 1.3 출시 메시지

- 냠냠이가 표정과 움직임으로 더 자연스럽게 반응해요.
- 캐릭터와 선택형 대화를 나누며 급식·편식·성장을 돌아볼 수 있어요.
- 오늘·급식표·성장·도감 화면을 더 아기자기하고 읽기 쉽게 다듬었어요.
- 급식표 날짜 상세, 알레르기 안내와 기록 저장 안정성을 개선했어요.
- 오늘 식단을 냠냠이가 AI로 쉽고 짧게 설명하고, 결과를 기기에 보관해 다시 볼 수 있어요.

## 로컬 검증 기준

- 실제 후보 설정과 메타데이터가 `1.3`/`36` 및 `com.h19h29.naymnaymlevelup`로 일치
- AI 결과에 생성형 AI 안내임을 표시하고, 명시적 동의·하루 1회·서버 측 비밀키 원칙을 검증
- Debug 테스트 앱과 서명하지 않은 Release 앱의 버전·빌드·번들 ID 확인
- 샘플 급식은 사용자가 체험 모드를 직접 선택한 경우에만 표시하며, 조회 실패나 급식 없는 날에 자동 대체하지 않음
- 알레르기 및 대표 영양소 안내는 교육용 참고 정보이며 학교 안내와 보호자 판단이 우선
- 급식판 사진은 기기 내부에만 저장하고 부모 공유나 서버 동기화에 포함하지 않음
- 광고, 인앱결제, 분석 SDK, 추적 SDK 없음
- App Privacy 초안과 Privacy Manifest 일치

실행 명령:

```sh
EXPECTED_MARKETING_VERSION=1.3 EXPECTED_BUILD_NUMBER=36 RELEASE_UPLOAD_REQUIRED=0 bash scripts/verify-release-readiness.sh
```

## 앱 소유자 확인이 필요한 항목

- Apple ID 로그인 또는 2FA
- Apple Developer Program 결제, 계약 또는 법적 동의
- 배포 인증서와 프로비저닝 권한
- App Privacy 답변 및 개인정보 처리방침의 최종 법적 정확성
- CloudKit 운영 환경 schema와 queryable index 배포 상태
- App Store Connect 업로드, TestFlight 그룹 연결 또는 App Review 제출

위 항목에 들어가기 전 멈추고 앱 소유자의 명시적 승인을 받는다. 인증정보나 비밀값은 문서·로그·Git에 남기지 않는다.
