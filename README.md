# 냠냠레벨업 iOS

## 소개
회원가입 없이 학교만 등록하면 바로 사용할 수 있는 무료 급식 영양교육 iPhone 앱.

## 핵심 기능
- 별명으로 시작
- 학교 검색/등록
- 오늘 급식 보기
- 월간 급식 보기
- 칼로리/영양정보 확인
- 알레르기 번호 쉬운 설명
- 안 먹는 반찬 클릭
- 놓칠 수 있는 영양소 안내
- 한 입 도전
- 경험치/레벨/뱃지
- 레벨별 캐릭터 변화
- 보호자 요약
- 설정/기록 초기화

## 개인정보 원칙
회원가입 없음, 서버 저장 없음, 광고 없음, 인앱결제 없음, 위치정보 없음.

앱 안에서도 다음 원칙을 안내합니다.
- 냠냠레벨업은 회원가입을 요구하지 않습니다.
- 이름, 이메일, 전화번호, 위치정보를 수집하지 않습니다.
- 별명, 학교 선택, 도전 기록, 알레르기 선택값은 사용자의 기기 내부에 저장됩니다.
- 서버로 전송하지 않습니다.
- 급식 조회를 위해 선택한 학교 코드와 날짜가 공공데이터 API 조회에 사용될 수 있습니다.
- 영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.

## 활용 데이터
- NEIS 학교기본정보
- NEIS 급식식단정보
- 식품영양성분DB는 추후 고도화 참고

## 개발 환경
- Xcode 26.5 확인
- SwiftUI
- iOS 16+
- Codex build ios apps 플러그인 사용
- 외부 Swift 패키지 없음

## API 키 설정
`Config.example.xcconfig`를 참고하여 `Config.xcconfig`를 만들고 `NEIS_API_KEY`를 입력한다.
`Config.xcconfig`는 Git에 올리지 않는다.

현재 프로젝트는 API 키가 없어도 빌드되고, 샘플 데이터 fallback으로 전체 흐름이 동작한다.

예시:

```xcconfig
NEIS_API_KEY = 발급받은_키
```

`NaymNaymLevelUp/Config/Base.xcconfig`가 루트의 `Config.xcconfig`를 optional include 하므로, 파일을 만든 뒤 다시 빌드하면 앱의 Info.plist에 `NEIS_API_KEY`가 주입된다.

## 실행 방법
Xcode에서 `NaymNaymLevelUp.xcodeproj` 열기
iPhone 시뮬레이터 선택
Build & Run

## 홍보 웹페이지
홍보용 반응형 웹페이지는 iOS 프로젝트와 분리된 `marketing-site` 폴더에 있습니다.

```bash
cd marketing-site
npm install
npm run dev
```

빌드는 다음 명령으로 확인합니다.

```bash
cd marketing-site
npm run build
```

## 주의사항
영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.
알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해야 합니다.

## 조사 메모
- Apple SwiftUI NavigationStack 문서 확인
- Apple URLSession 문서 확인
- Apple UserDefaults 문서 확인
- Apple XCTest 문서 확인
- NEIS 학교기본정보/급식식단정보 Open API 문서 확인
- App Store Connect App Privacy 안내 확인
- SwiftUI Calendar, Onboarding, Confetti 관련 MIT 공개 프로젝트는 참고만 하고 1.0에는 의존성을 추가하지 않음
