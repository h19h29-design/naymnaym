# 개발 기록

## 2026-06-18
- 로컬 저장소는 커밋 없는 초기 Git 상태였고 원격 remote가 설정되어 있지 않았다.
- `https://github.com/h19h29-design/naymnaym.git`는 조회 가능하지만 refs가 없어 비어 있는 원격 저장소로 확인했다.
- SwiftUI 네이티브 iOS 16+ 앱 구조로 스캐폴딩했다.
- 회원가입/로그인/서버/광고/분석 SDK 없이 로컬 저장 기반으로 구현했다.
- NEIS API 키가 없거나 실제 급식 조회에 실패해도 샘플 학교/급식 데이터로 자동 fallback하지 않는다.
- 샘플 데이터는 사용자가 명시적으로 체험 모드를 선택한 경우에만 표시한다.
- 외부 Swift 패키지는 추가하지 않았다.

## 구현 범위
- 온보딩, 별명 입력, 학교 검색, 알레르기 선택
- 오늘 급식, 반찬별 영양소 손실 안내, 한 입 도전, EXP/뱃지/레벨
- 월간 식단 캘린더, 레벨/뱃지, 보호자 요약, 설정/초기화
- `UserDefaults + Codable` 기반 로컬 저장
- API 키 비밀값 제외 및 `.gitignore` 구성

## 2026-06-20
- `UserMode`, `ThemeProfile`, `MealDataState`, `EatingStatus`, `MealRecord`, 부모 연동 모델을 추가했다.
- 초등학생/중학생/고등학생/부모 모드와 모드별 테마를 추가했다.
- 매일 첫 진입 인트로와 체험 모드/보호자 모드 진입을 추가했다.
- 실제 NEIS 급식 조회 상태를 `live`, `noMeal`, `error`, `missingAPIKey`, `sampleSchool`, `demo`로 구분했다.
- 오늘 급식 화면에서 알레르기 관련 메뉴는 한 입 도전을 잠그고 안전 안내를 우선 표시한다.
- 급식판 사진 선택/촬영, 로컬 파일 저장, 부모 공유 선택 흐름을 추가했다.
- 부모 대시보드, 칭찬 카드, CloudKit 초대 코드 기반 부모 연결 구조를 추가했다.
- 부모 연결은 아이별 `childLinkId`로 먹은 정도, 한 입 도전, 알레르기 주의, 공유 사진을 분리한다.
- 홍보 페이지 문구를 “급식표 앱”이 아닌 식습관 코칭 앱 메시지로 조정했다.

## 2026-06-24
- App Store 제출 초안을 `release/AppStoreMetadata/` 경로로 추가했다.
- 마케팅 사이트에 데이터 안전 안내 페이지를 추가했다.
- XP 보너스 수치를 1.0 요구사항에 맞춰 연속 기록 +5, 다양한 음식군 +5, 알레르기 안전 확인 +10으로 정리했다.
- SNS 공유 카드에 오늘 기록 카드를 추가했다.
- 변경분 업로드 준비를 위해 앱 빌드 번호를 12로 올렸다.
- build 12를 unsigned archive로 생성하고 App Store Connect remote signing export 후 TestFlight CLI 업로드까지 완료했다.
- 설정 화면에 공개 개인정보 처리방침, 지원 안내, 데이터 안전 안내 URL을 바로 열 수 있는 링크를 추가했다.
- 변경분 반영을 위해 앱 빌드 번호를 13으로 올리고 TestFlight CLI 업로드까지 완료했다.

## 2026-06-25
- CloudKit record type/field 계약과 Privacy Manifest 수집 데이터 항목을 XCTest로 고정했다.
- 출시 인트로에서 사용하는 로고, 마스코트, 배경, 기능 아이콘 에셋이 앱 번들에 포함되는지 XCTest로 고정했다.
- plist lint, 앱 버전/빌드/Bundle ID, CloudKit entitlement, 권한 문구, App Store 아이콘/스크린샷 규격, 공개 URL 상태를 확인하는 출시 검증 스크립트를 추가했다.
- 로컬 API 키를 출력하지 않고 NEIS 학교 검색과 급식식단정보 실제 응답을 확인하는 smoke 스크립트를 추가했다.
- NEIS smoke 기본 기준을 현재 월 대신 등촌고등학교 2026년 6월로 고정하고, 환경변수로 다른 학교/월을 확인할 수 있게 했다.
- 제출 전 대기 메모를 build 13 업로드 완료 상태와 남은 App Store Connect/CloudKit 작업 기준으로 갱신했다.
- 추가 변경은 테스트/문서 보강이므로 build 13 바이너리 재업로드는 하지 않는다.
