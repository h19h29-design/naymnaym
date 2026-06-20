# 1.0 출시 준비 감사

작성일: 2026-06-20

## 현재 결론

코드, 테스트, 시뮬레이터, Release archive, App Store 제출 자료는 1.0 후보 상태까지 준비됐다. TestFlight용 signed build 1.0 (8) IPA는 생성 및 업로드까지 완료됐다. 외부 테스트 공개는 App Store Connect에서 build 8 처리 완료 확인, 외부 그룹 연결, 심사 제출이 남아 있다.

## 요구사항별 증거

| 요구사항 | 현재 상태 | 증거 |
| --- | --- | --- |
| 회원가입 없이 사용 | 완료 | 로컬 `UserDefaults + Codable` 저장 구조, 로그인/계정 SDK 없음 |
| 아이가 학교 등록 | 완료 | `SchoolSearchService.searchSchools`가 NEIS `schoolInfo` 호출, `UserProfile.school`에 office/school code 저장 |
| 실제 NEIS 급식 조회 | 완료 | `MealService.fetchMonthlyMeals`가 `mealServiceDietInfo` 호출 |
| 샘플 자동 fallback 금지 | 완료 | `MealDataState.demo`만 `usesSample == true`; API 키 없음/오류/데이터 없음/샘플 학교는 빈 결과와 안내 상태 반환 |
| API 키 없음 안내 | 완료 | `NEISClientError.missingAPIKey`를 `missingAPIKey` 상태로 표시 |
| 급식 없는 날 안내 | 완료 | `noMeal` 상태와 오늘 급식 없음 문구 표시 |
| 어려운 반찬 기록 | 완료 | `EatingStatus`, `DifficultyReason`, `MealRecord` 저장 |
| 한 입 도전 성장 | 완료 | `ChallengeRecord`, EXP, badge, `PlayerProgress.currentSkin(for:)` |
| 알레르기 주의 | 완료 | 선택 알레르기와 메뉴 allergy code 교차 시 한 입 도전 잠금 및 안전 안내 |
| 초등/중등/고등/부모 모드 | 완료 | `UserMode`, `ThemeProfile`, 모드별 `CharacterSkin` |
| 부모 다자녀 연결 | 코드 완료, 운영 설정 확인 필요 | CloudKit `ParentLink` 초대 코드, `childLinkId` 기반 아이별 기록 분리, 아이별 주간 변화 요약, build 8에 Production CloudKit entitlement 포함 |
| 부모 공유 사진 | 코드 완료, 운영 설정 확인 필요 | 공유 선택 사진만 `SharedMealPhoto` + CKAsset 생성, build 8에 Production CloudKit entitlement 포함 |
| 개인정보/지원 안내 | 완료, 공개 배포 필요 | 앱 내 설정 화면, `docs/PRIVACY_POLICY_DRAFT.md`, `docs/SUPPORT.md`, `marketing-site/dist/privacy.html`, `marketing-site/dist/support.html` |
| App Store 스크린샷 | 완료 | `docs/app-store-screenshots/iphone-6-9-upload/*.jpg`, 1320x2868, alpha 없음 |
| Privacy Manifest | 완료 | `NaymNaymLevelUp/PrivacyInfo.xcprivacy`와 build 8 IPA에 UserDefaults 사유, 선택 부모 공유용 수집 데이터 타입, 추적 없음 선언 포함 |

## 실제 NEIS 확인

2026-06-20 현재 로컬 `Config.xcconfig`에는 NEIS API 키가 설정되어 있다. 키 값은 출력하지 않았다.

- 키 길이: 32
- 검색 학교: 등촌고등학교
- `officeCode`: `B10`
- `schoolCode`: `7010700`
- 2026년 6월 중식 row 수: 19
- 첫 row 필드: `DDISH_NM`, `CAL_INFO`, `NTR_INFO` 존재

## 최근 검증

- XCTest: 42개 통과
- Debug build/install/run simulator: 통과
- Release/generic iOS archive + App Store Connect remote-signed export: 통과
- TestFlight signed IPA: `build/TestFlightExportBuild8Signed/NaymNaymLevelUp.ipa`
- TestFlight build: `1.0 (8)`
- TestFlight upload: CLI 업로드 성공, App Store Connect 처리 상태 확인 필요
- `git diff --check`: 통과
- `App/Info.plist`, `PrivacyInfo.xcprivacy`, `NaymNaymLevelUp.entitlements`: `plutil -lint` 통과
- build 8 IPA 내부 `Info.plist`: `plutil -lint` 통과
- build 8 IPA 내부 `PrivacyInfo.xcprivacy`와 수집 데이터 타입 포함 확인
- build 8 IPA 내부 `ITSAppUsesNonExemptEncryption = false` 확인
- build 8 IPA 내부 `beta-reports-active = true`, CloudKit Production entitlement 확인
- 최신 XCTest 결과: `/Users/mac-mini/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/result-bundles/test_sim_2026-06-20T08-56-23-779Z_pid97415_f32cbc78.xcresult`
- 시뮬레이터 스냅샷: 실제 학교 등촌고등학교 상태에서 2026-06-20 토요일 `급식 데이터 없음` 안내 표시, `build/verification/simulator-build8-20260620-175731.png`
- 2026-06-20 추가 갱신: 부모 모드에서 아이별 주간 한 입 도전 변화 요약을 표시하도록 보강했고, build 8 signed IPA를 App Store Connect에 업로드 완료

## 남은 외부 작업

아래 항목은 로컬 코드로 완료할 수 없고 Apple Developer/App Store Connect 계정에서 확인 또는 처리해야 한다.

1. App Store Connect에서 build 8 처리 완료 여부 확인
2. build 8을 내부/외부 테스트 그룹에 연결
3. 외부 테스트 그룹 공개 링크에 build 8이 연결됐는지 확인
4. 외부 테스트 심사 제출
5. App Privacy 답변에 선택 부모 공유 데이터 타입 반영
6. CloudKit Dashboard public database schema 배포 상태 확인
7. CloudKit query index 설정 확인
   - `ParentLink.inviteCode`
   - `SharedMealRecord.childLinkId`
   - `SharedChallengeRecord.childLinkId`
   - `SharedMealPhoto.childLinkId`
8. CloudKit public database 권한 확인
   - 앱 사용자가 `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto`를 생성/수정할 수 있어야 함
   - 초대 코드 조회는 정확한 `inviteCode` 조건에서만 동작해야 함
9. 개인정보 처리방침 URL과 지원 URL 공개 상태 확인
   - 정적 출시 사이트 산출물: `marketing-site/dist/`

## 참고 파일

- `docs/TESTFLIGHT_APP_STORE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/APP_STORE_SCREENSHOTS.md`
- `docs/PRIVACY_POLICY_DRAFT.md`
- `docs/SUPPORT.md`
