# App Store 제출 전 대기 메모

## 자동 진행 가능 항목

- 로컬 빌드와 테스트: 완료
- 시뮬레이터 스크린샷 생성: 완료
- App Store 메타데이터 초안 작성: 완료
- Privacy 초안 작성: 완료
- Release build 1.0 (15) signed archive/export: 완료
- build 15 IPA CloudKit entitlement 검사: 완료
- TestFlight build 1.0 (15) CLI 업로드: 완료
- App Store Connect build 15 처리 완료 확인: 완료
- TestFlight 내부 `윈드` / 외부 `패밀리` 그룹 연결: 완료
- 외부 TestFlight 공개 링크 활성화: `https://testflight.apple.com/join/3A3rKarB`
- 외부 TestFlight 베타 심사 제출 및 `테스트 중` 상태 확인: 완료
- 출시 검증 스크립트 실행: `scripts/verify-release-readiness.sh`

## Hard Blocker

아래 상황에서는 자동 제출을 멈추고 앱 소유자 확인이 필요합니다.

- Apple ID 로그인 필요
- 2FA 인증 필요
- Apple Developer Program 결제 또는 계약 동의 필요
- App Store Connect 계정 소유자만 가능한 법적 동의 필요
- 인증서 또는 프로비저닝 권한 없음
- 개인정보처리방침 URL이 공개 URL과 다르거나 App Store Connect 입력 전 법적 확인이 필요한 경우
- App Privacy 답변을 사실과 다르게 입력해야 하는 상황
- 실제 App Review `Submit for Review` 버튼을 누르기 직전

## 현재 운영 확인 필요 항목

- App Store Connect에 업데이트된 Apple Developer Program 사용권 계약 배너가 계속 보이면 계정 소유자가 계약 검토 및 동의
- `release/AppStoreMetadata/app-privacy-draft.md`의 App Store Connect 입력 매트릭스 기준으로 App Privacy 최종 입력
- CloudKit container `iCloud.com.h19h29.naymnaymlevelup` 운영 환경 schema 배포
- public database record type과 queryable index 확인
- 개인정보 처리방침/지원/데이터 안전 페이지는 GitHub Pages에 공개 완료. App Store Connect 입력 전 최종 법률/표기 확인 필요
