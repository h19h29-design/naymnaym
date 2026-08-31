# 급식레벨업 1.2 (33) 제출 전 대기 메모

## 현재 후보

- 앱 이름: 급식레벨업
- Bundle ID: `com.h19h29.naymnaymlevelup`
- 마케팅 버전: `1.2`
- 빌드: `33`
- 검증 모드: `RELEASE_UPLOAD_REQUIRED=0`

이 작업에서는 App Store Connect 업로드나 App Review 제출을 수행하지 않았다. 서명된 archive·IPA·업로드 로그는 현재 로컬 후보 검증의 필수 조건이 아니며, 업로드가 별도로 승인된 경우에만 `RELEASE_UPLOAD_REQUIRED=1`로 검증한다.

## 1.2 출시 메시지

- 캐릭터 성장 단계가 12단계로 늘어났어요.
- 일간·주간·월간 급식표에서 선택한 날짜의 메뉴·알레르기·영양 상세를 확인할 수 있어요.
- 메뉴별 대표 영양소를 부담 없는 교육용 안내로 확인할 수 있어요.
- 음식 아이콘과 화면 디자인을 더 알아보기 쉽게 개선했어요.

## 로컬 검증 기준

- 실제 후보 설정과 메타데이터가 `1.2`/`33` 및 `com.h19h29.naymnaymlevelup`로 일치
- Debug 테스트 앱과 서명하지 않은 Release 앱의 버전·빌드·번들 ID 확인
- 샘플 급식은 사용자가 체험 모드를 직접 선택한 경우에만 표시하며, 조회 실패나 급식 없는 날에 자동 대체하지 않음
- 알레르기 및 대표 영양소 안내는 교육용 참고 정보이며 학교 안내와 보호자 판단이 우선
- 급식판 사진은 기기 내부에만 저장하고 부모 공유나 서버 동기화에 포함하지 않음
- 광고, 인앱결제, 분석 SDK, 추적 SDK 없음
- App Privacy 초안과 Privacy Manifest 일치

실행 명령:

```sh
EXPECTED_MARKETING_VERSION=1.2 EXPECTED_BUILD_NUMBER=33 RELEASE_UPLOAD_REQUIRED=0 bash scripts/verify-release-readiness.sh
```

## 앱 소유자 확인이 필요한 항목

- Apple ID 로그인 또는 2FA
- Apple Developer Program 결제, 계약 또는 법적 동의
- 배포 인증서와 프로비저닝 권한
- App Privacy 답변 및 개인정보 처리방침의 최종 법적 정확성
- CloudKit 운영 환경 schema와 queryable index 배포 상태
- App Store Connect 업로드, TestFlight 그룹 연결 또는 App Review 제출

위 항목에 들어가기 전 멈추고 앱 소유자의 명시적 승인을 받는다. 인증정보나 비밀값은 문서·로그·Git에 남기지 않는다.
