# 급식레벨업 앱인토스 등록 자료

## 최초 등록

- 앱 이름: `급식레벨업`
- 영어 앱 이름: `Meal Level Up`
- 권장 appName: `nyam-levelup`
  - 콘솔에서 사용 가능 여부를 확인한 뒤에만 확정한다.
  - appName은 최초 등록 후 수정할 수 없으므로 임의의 대체값을 저장하지 않는다.
- 앱 유형: `비게임`

## 기본 정보

- 부제: `오늘 급식을 기록하고 다람쥐를 키워요`
- 상세 설명:

  급식레벨업은 중학교와 고등학교의 오늘 급식 메뉴를 확인하고,
  메뉴별 식사 도전을 기록하며 다람쥐 캐릭터를 성장시키는 서비스입니다.
  첫 실행에서 별명, 학교 유형, 학교와 알레르기 항목을 선택합니다.
  오늘 급식 화면에서 알레르기 표시를 확인하고 메뉴별로 먹은 정도나
  한입 도전을 기록하면 XP가 누적되어 일곱 단계의 성장 이미지가
  바뀝니다. 별명, 학교, 알레르기, 기록과 XP는 이 기기의 토스
  저장소에만 저장되며 설정에서 수정하거나 모두 삭제할 수 있습니다.
  학교를 등록하지 않고 저장되지 않는 체험 모드도 사용할 수 있습니다.

- 개인정보 처리방침:
  `https://h19h29-design.github.io/naymnaym/privacy.html`
- 문의 및 지원:
  `https://h19h29-design.github.io/naymnaym/support.html`
- 고객센터 이메일 또는 연락처:
  - 콘솔 소유자가 공개 사용을 승인한 연락처를 입력한다.
  - 개인 이메일을 추정하거나 자동 입력하지 않는다.
- 문의 채널:
  `https://github.com/h19h29-design/naymnaym/issues`

## 노출 정보

- 앱 로고:
  `apps-in-toss/release-assets/app-icon-600.png`
  - 공개 URL:
    `https://h19h29-design.github.io/naymnaym/app-icon-600.png`
  - 600 × 600 PNG
  - 불투명 배경
- 썸네일:
  `apps-in-toss/release-assets/thumbnail-1932x828.png`
  - 1932 × 828 PNG
  - 불투명 배경
  - 앱의 급식 기록과 다람쥐 성장 경험을 자체 제작 캐릭터로 표현
- 검색 키워드 후보:
  - `급식`
  - `학교급식`
  - `한입도전`
  - `식사기록`
  - `다람쥐성장`
- 카테고리:
  - 콘솔에서 제공하는 실제 선택지 중 급식·식생활·교육 성격에 가장
    가까운 비게임 카테고리를 선택하고 저장 전에 다시 확인한다.

## 기능 등록

- 기능 이름: `오늘 급식`
- 진입 경로: `/today`
- 스킴: `intoss://nyam-levelup/today`
- QR 테스트 스킴: `intoss-private://nyam-levelup/today`

appName이 달라지면 위 스킴과 모든 환경 설정을 같은 값으로 일괄
갱신한다.

## CORS 허용 출처

- 실제 서비스: `https://nyam-levelup.apps.tossmini.com`
- QR 테스트: `https://nyam-levelup.private-apps.tossmini.com`

appName 확정 전에는 Supabase의 `NEIS_ALLOWED_ORIGINS`에 등록하지 않는다.

## 이번 버전 메모

아이폰 앱과 같은 숲 배경의 오늘 급식 홈, 급식 기록 시트, 성장·도감
탭을 적용했습니다. 중학교·고등학교 선택에 맞춰 학교 검색 결과가
정확히 표시되도록 검색 조건도 보완했습니다.

## 심사 전 확인

- 앱 이름, appName, 아이콘 URL과 `granite.config.ts` 값이 일치한다.
- 개인정보 처리방침과 지원 페이지가 HTTP 200으로 열린다.
- 실제 학교 선택 상태에서 오류를 샘플 급식으로 대체하지 않는다.
- 체험 기록은 저장 및 XP에 반영되지 않는다.
- 로컬 데이터 삭제가 프로필, 식사 기록, XP와 캐시를 모두 삭제한다.
- iOS와 Android QR 환경에서 `/today`, 학교 검색, 급식 조회와 뒤로가기를
  각각 확인한다.
