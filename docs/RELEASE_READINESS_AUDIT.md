# 1.0 출시 준비 감사

작성일: 2026-06-25

## 현재 결론

코드, 테스트, 시뮬레이터, App Store 제출 자료는 1.0 후보 수준까지 준비됐다. 다만 TestFlight용 signed build 1.0 (14) IPA는 CLI 업로드까지 완료됐지만 실제 앱 서명 entitlements에 iCloud/CloudKit 항목이 없어 부모 CloudKit 연동을 포함한 최종 외부 테스트/출시 후보로 사용할 수 없다. build 14는 App Store Connect 처리 확인 전이라도 출시 후보에서 제외하고, CloudKit entitlement가 실제 signed app에 포함되는 build 15 이상을 다시 archive/export/upload해야 한다.

### 2026-06-25 build 14 갱신

build 14 후보에서 부모 공유 도전 기록을 선택 공유 항목으로만 제한하고, 전체 데이터 삭제 시 orphan 사진 파일까지 제거하도록 보강했다. XcodeBuildMCP 기준 iPhone 17, iPhone 16, iPhone SE 시뮬레이터 build/run과 전체 테스트는 통과했다. Release archive는 unsigned archive로 생성한 뒤 App Store Connect remote signing export를 통해 Cloud Managed Apple Distribution 인증서와 App Store 프로비저닝으로 서명했고, 동일 archive에서 upload destination으로 CLI 업로드까지 성공했다.

이후 업로드된 IPA를 직접 풀어 검사한 결과, embedded provisioning profile은 iCloud container `iCloud.com.h19h29.naymnaymlevelup`와 CloudKit service wildcard `*`를 허용한다. 하지만 실제 signed app을 `codesign -d --entitlements :-`로 검사하면 `application-identifier`, `beta-reports-active`, team identifier, `get-task-allow`만 있고 아래 항목이 없다.

- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services = CloudKit`

프로젝트의 `NaymNaymLevelUp.entitlements`, Xcode build 설정, Release archive 중간 `.xcent`에는 iCloud container와 CloudKit service가 모두 존재한다. build 14 archive는 unsigned 상태였고, unsigned archive를 App Store Connect remote signing으로 export한 IPA에는 앱 entitlements가 반영되지 않았다. `iCloudContainerEnvironment = Production`을 명시한 별도 export도 embedded profile은 허용 상태였지만 signed app entitlements는 동일하게 누락됐다. 반대로 signed archive 재시도는 올바른 `.xcent` 생성과 `codesign` 단계까지 도달했으나 macOS signing keychain/certificate 접근 대기 상태에서 중단했다. 따라서 다음 차단 지점은 Apple Developer capability 자체보다 로컬 signing keychain/certificate 접근을 허용해 signed archive를 만드는 것이다.

build 14 확인:

- XCTest: 66개 통과
- iPhone 17, iPhone 16, iPhone SE Debug build/install/run: 통과
- `git diff --check`: 통과
- NEIS 실제 호출: `등촌고등학교` 검색 성공, `mealServiceDietInfo` 2026년 6월 중식 row 19개, `DDISH_NM/CAL_INFO/NTR_INFO` 필드 확인
- 인트로 검증: `build/verification/intro-iphone17-final.jpg`, `build/verification/intro-iphone16-final.jpg`, `build/verification/intro-iphone-se-final.jpg`, `build/verification/intro-animation-final.mov`
- App Store 후보 스크린샷: `docs/app-store-screenshots/iphone-6-9-upload/*.jpg` 10장, 온보딩/오늘 급식/한 입 도전/레벨업/부모 요약/알레르기 안전/공유 카드 포함
- Share Sheet 확인: `build/verification/share-sheet-iphone16.jpg`
- Release unsigned archive: `build/NaymNaymLevelUp-build14-unsigned.xcarchive`
- App Store Connect remote-signed IPA: `build/TestFlightExportBuild14Signed/NaymNaymLevelUp.ipa`
- TestFlight CLI upload: 성공, App Store Connect 처리 상태 확인 필요

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
| 부모 다자녀 연결 | 코드 완료, 릴리즈 서명 차단 | CloudKit `ParentLink` 초대 코드, `childLinkId` 기반 아이별 기록 분리, 아이별 주간 변화 요약, 기록 공유/사진 공유/도전 기록 공유 토글 분리. 단, build 14 signed IPA에 CloudKit entitlement가 없어 build 15 이상 재서명/재업로드 필요 |
| 부모 공유 사진 | 코드 완료, 릴리즈 서명 차단 | 공유 선택 사진만 `SharedMealPhoto` + CKAsset 생성, 사진 공유는 기록 공유가 켜진 경우에만 선택 가능, 기록 공유 해제 시 사진 공유도 비공유로 정리. 단, build 14 signed IPA에 CloudKit entitlement가 없어 build 15 이상 재서명/재업로드 필요 |
| 데이터 삭제 범위 | 완료 | `resetChallengeRecords`는 도전/식사 기록만 지우고 프로필/부모 연결/사진 파일은 유지, `resetAllData`는 프로필/기록/XP/부모 연결/사진 디렉터리/메타데이터까지 삭제하도록 XCTest 고정 |
| 개인정보/지원 안내 | 완료, 공개 배포 완료 | 앱 내 설정 화면, 웹 개인정보 처리방침/지원/데이터 안전 링크, `docs/PRIVACY_POLICY_DRAFT.md`, `docs/SUPPORT.md`, `marketing-site/dist/privacy.html`, `marketing-site/dist/support.html`, GitHub Pages URL 200 확인 |
| App Store 스크린샷 | 완료 | `docs/app-store-screenshots/iphone-6-9-upload/*.jpg` 10장, 1320x2868, alpha 없음, 온보딩/오늘 급식/한 입 도전/레벨업/부모 요약/알레르기 안전/공유 카드 포함 |
| Privacy Manifest | 완료 | `NaymNaymLevelUp/PrivacyInfo.xcprivacy`와 build 14 export에 UserDefaults 사유, 선택 부모 공유용 수집 데이터 타입, 추적 없음 선언 포함 |

## 실제 NEIS 확인

2026-06-20 현재 로컬 `Config.xcconfig`에는 NEIS API 키가 설정되어 있다. 키 값은 출력하지 않았다.

- 키 길이: 32
- 검색 학교: 등촌고등학교
- `officeCode`: `B10`
- `schoolCode`: `7010700`
- 2026년 6월 중식 row 수: 19
- 첫 row 필드: `DDISH_NM`, `CAL_INFO`, `NTR_INFO` 존재

## 최근 검증

- XCTest: 66개 통과
- Debug build/install/run simulator: iPhone 17, iPhone 16, iPhone SE 통과
- Release/generic iOS archive + App Store Connect remote-signed export: 통과
- TestFlight signed IPA: `build/TestFlightExportBuild14Signed/NaymNaymLevelUp.ipa`
- TestFlight build: `1.0 (14)`
- TestFlight upload: CLI 업로드 성공, App Store Connect 처리 상태 확인 필요
- `git diff --check`: 통과
- `scripts/verify-release-readiness.sh`: 앱 버전/빌드/Bundle ID, 프로젝트 CloudKit entitlement, 권한 문구, 추적/위치 권한 부재, 외부 광고/분석/로그인/결제 SDK 부재, build 14 IPA/업로드 로그 증거, embedded profile CloudKit entitlement, signed IPA CloudKit entitlement, App Store 아이콘/스크린샷, 공개 URL 검증을 확인한다. 현재 build 14는 signed app iCloud container entitlement 누락에서 의도적으로 실패해야 한다.
- `scripts/smoke-neis-live.sh`: API 키 비노출 방식으로 등촌고등학교 2026년 6월 `schoolInfo`, `mealServiceDietInfo` 실제 응답 검증
- `App/Info.plist`, `PrivacyInfo.xcprivacy`, `NaymNaymLevelUp.entitlements`: `plutil -lint` 통과
- build 14 export summary: buildNumber `14`, versionNumber `1.0`, `beta-reports-active = true`, Cloud Managed Apple Distribution 서명 확인. 단, 실제 IPA signed entitlements에는 iCloud/CloudKit이 없어 release hold.
- GitHub Pages 출시 사이트: `privacy.html`, `support.html`, `data-safety.html` HTTPS 200 확인
- 2026-06-24 추가 검증: 설정 화면 공개 URL 링크 추가 후 iOS Simulator build 통과, XCTest 55개 통과
- 2026-06-25 추가 검증: CloudKit record type/field 계약, Privacy Manifest 수집 데이터 항목, 출시 인트로 필수 에셋 번들링, 전체 데이터 삭제/도전 기록 삭제 범위, 부모 공유 도전 기록 선택 공유 gate 고정 테스트 추가 후 XCTest 66개 통과
- 최신 XCTest 결과: `/Users/mac-mini/Library/Developer/XcodeBuildMCP/workspaces/workspace-f281014df961/result-bundles/test_sim_2026-06-24T17-28-20-518Z_pid66299_efcfa4ca.xcresult`
- 시뮬레이터 스냅샷: `build/verification/intro-iphone17-final.jpg`, `build/verification/intro-iphone16-final.jpg`, `build/verification/intro-iphone-se-final.jpg`, `build/verification/share-sheet-iphone16.jpg`
- 2026-06-24 추가 갱신: 설정 화면 공개 URL 링크, 부모 모드, XP 정책, SNS 공유 카드, App Store 제출 자료를 반영한 build 13 signed IPA를 App Store Connect에 업로드 완료
- 2026-06-25 추가 갱신: 부모 공유 도전 기록 선택 공유 gate와 사진 삭제 보강을 반영한 build 14 signed IPA를 App Store Connect에 업로드 완료

## 남은 외부 작업

아래 항목은 로컬 코드로 완료할 수 없고 Apple Developer/App Store Connect 계정에서 확인 또는 처리해야 한다.

1. 로컬 signing keychain/certificate 접근 허용
2. `scripts/release-testflight-build.sh 15`로 build 15 signed archive/export 및 IPA entitlement 검증
3. exported IPA의 embedded profile이 iCloud container와 CloudKit service를 허용하는지 확인
4. exported IPA의 signed app entitlements에 iCloud container와 CloudKit service가 포함됐는지 확인
5. `UPLOAD=1 scripts/release-testflight-build.sh 15`로 CloudKit entitlement 검증 통과 빌드를 TestFlight에 업로드
6. App Store Connect에서 build 15 이상 처리 완료 여부 확인
7. build 15 이상을 내부/외부 테스트 그룹에 연결
8. 외부 테스트 그룹 공개 링크가 build 15 이상을 가리키는지 확인
9. 외부 테스트 심사 제출
10. App Privacy 답변에 선택 부모 공유 데이터 타입 반영
11. CloudKit Dashboard public database schema 배포 상태 확인
12. CloudKit queryable index 설정 확인
   - `ParentLink.inviteCode`
   - `SharedMealRecord.childLinkId`
   - `SharedChallengeRecord.childLinkId`
   - `SharedMealPhoto.childLinkId`
   - `createdAt` 최신순 정렬은 앱 내부에서 처리하므로 sortable index는 필요 없음
13. CloudKit public database 권한 확인
   - 앱 사용자가 `ParentLink`, `SharedMealRecord`, `SharedChallengeRecord`, `SharedMealPhoto`를 생성/수정할 수 있어야 함
   - 초대 코드 조회는 정확한 `inviteCode` 조건에서만 동작해야 함
14. App Store Connect 입력 전 개인정보 처리방침, 지원, 데이터 안전 문구의 최종 법률/표기 확인
   - 개인정보 처리방침 URL: `https://h19h29-design.github.io/naymnaym/privacy.html`
   - 지원 URL: `https://h19h29-design.github.io/naymnaym/support.html`
   - 데이터 안전 안내 URL: `https://h19h29-design.github.io/naymnaym/data-safety.html`

## 참고 파일

- `docs/TESTFLIGHT_APP_STORE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/APP_STORE_SCREENSHOTS.md`
- `docs/PRIVACY_POLICY_DRAFT.md`
- `docs/SUPPORT.md`
