# 1.0 출시 준비 감사

작성일: 2026-06-20

## 현재 결론

코드, 테스트, 시뮬레이터, unsigned Release archive, App Store 제출 자료는 1.0 후보 상태까지 준비됐다. 실제 TestFlight 업로드와 외부 테스트 공개는 Apple Developer/App Store Connect 계정에서 서명, CloudKit, 앱 레코드 설정을 마친 뒤 진행해야 한다.

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
| 부모 다자녀 연결 | 코드 완료, 계정 설정 필요 | CloudKit `ParentLink` 초대 코드, `childLinkId` 기반 아이별 기록 분리 |
| 부모 공유 사진 | 코드 완료, 계정 설정 필요 | 공유 선택 사진만 `SharedMealPhoto` + CKAsset 생성 |
| 개인정보/지원 안내 | 완료 | 앱 내 설정 화면, `docs/PRIVACY_POLICY_DRAFT.md`, `docs/SUPPORT.md`, marketing site static pages |
| App Store 스크린샷 | 완료 | `docs/app-store-screenshots/iphone-6-9-upload/*.jpg`, 1320x2868, alpha 없음 |
| Privacy Manifest | 완료 | `NaymNaymLevelUp/PrivacyInfo.xcprivacy`, archive 포함 확인 |

## 실제 NEIS 확인

2026-06-20 현재 로컬 `Config.xcconfig`에는 NEIS API 키가 설정되어 있다. 키 값은 출력하지 않았다.

- 키 길이: 32
- 검색 학교: 등촌고등학교
- `officeCode`: `B10`
- `schoolCode`: `7010700`
- 2026년 6월 중식 row 수: 19
- 첫 row 필드: `DDISH_NM`, `CAL_INFO`, `NTR_INFO` 존재

## 최근 검증

- XCTest: 35개 통과
- Debug build/run simulator: 통과
- Release/generic iOS unsigned archive: 통과
- `git diff --check`: 통과
- `Info.plist`, `PrivacyInfo.xcprivacy`, `NaymNaymLevelUp.entitlements`: `plutil -lint` 통과
- `build/NaymNaymLevelUp.xcarchive` 내부 `PrivacyInfo.xcprivacy` 포함 확인
- 시뮬레이터 스냅샷: 실제 학교 등촌고등학교 상태에서 2026-06-20 토요일 `급식 데이터 없음` 안내 표시

## 남은 외부 계정 작업

아래 항목은 로컬 코드로 완료할 수 없고 Apple Developer/App Store Connect 계정에서 처리해야 한다.

1. Xcode Signing & Capabilities에서 Apple Team 선택
2. Apple Developer 계정에서 `iCloud.com.h19h29.naymnaymlevelup` container 생성 또는 연결
3. CloudKit Dashboard public database schema 배포
4. CloudKit query index 설정
   - `ParentLink.inviteCode`
   - `SharedMealRecord.childLinkId`
   - `SharedChallengeRecord.childLinkId`
   - `SharedMealPhoto.childLinkId`
5. CloudKit public database 권한 확인
   - 앱 사용자가 `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto`를 생성/수정할 수 있어야 함
   - 초대 코드 조회는 정확한 `inviteCode` 조건에서만 동작해야 함
6. App Store Connect 앱 레코드 생성
7. 개인정보 처리방침 URL과 지원 URL 공개
8. 실제 서명 archive 생성
9. TestFlight 업로드
10. 외부 테스트 그룹과 공개 초대 링크 생성

## 참고 파일

- `docs/TESTFLIGHT_APP_STORE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/APP_STORE_SCREENSHOTS.md`
- `docs/PRIVACY_POLICY_DRAFT.md`
- `docs/SUPPORT.md`
