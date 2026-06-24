# App Store 제출 전 대기 메모

## 자동 진행 가능 항목

- 로컬 빌드와 테스트
- 시뮬레이터 스크린샷 생성
- App Store 메타데이터 초안 작성
- Privacy 초안 작성
- Archive 생성 시도
- Apple 계정 로그인 상태에서 권한이 충분한 경우 TestFlight 업로드 시도

## Hard Blocker

아래 상황에서는 자동 제출을 멈추고 앱 소유자 확인이 필요합니다.

- Apple ID 로그인 필요
- 2FA 인증 필요
- Apple Developer Program 결제 또는 계약 동의 필요
- App Store Connect 계정 소유자만 가능한 법적 동의 필요
- 인증서 또는 프로비저닝 권한 없음
- 개인정보처리방침 URL 미확정
- App Privacy 답변을 사실과 다르게 입력해야 하는 상황
- 실제 App Review `Submit for Review` 버튼을 누르기 직전

## 현재 운영 확인 필요 항목

- CloudKit container `iCloud.com.h19h29.naymnaymlevelup` 운영 환경 schema 배포
- public database record type과 queryable index 확인
- 개인정보 처리방침/지원/데이터 안전 페이지 공개 URL 확정
- TestFlight 외부 그룹과 공개 링크에 build 12 연결
