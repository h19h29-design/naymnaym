# 급식레벨업 Apps in Toss Lite v2

학교 급식 조회, 알레르기 주의, 식사 기록, XP 성장을 네 개 경로로 제공하는 WebView 미니앱이다.

- `/onboarding`: 초·중·고 학교 검색, 선택 별명, 알레르기 설정
- `/today`: 오늘 급식, 12단계 성장, 메뉴별 최종 기록
- `/week`: 서울 기준 이번 주 월요일부터 일요일까지의 급식
- `/settings`: 프로필 수정, 안내 링크, 확인 후 전체 삭제

하단 탭은 오늘, 주간, 설정 세 개뿐이다. 성장 정보는 오늘 화면에 포함하며 도감·월간·로그인·광고·분석은 포함하지 않는다.

## 환경

`.env.example`을 참고해 `.env.local`에 다음 값을 둔다.

- `VITE_NEIS_PROXY_URL`: 현재 운영 프록시 URL
- `VITE_NEIS_CLIENT_TOKEN`: 공개 앱 요청을 식별하는 client token

한 버전 동안만 `VITE_SUPABASE_ANON_KEY`를 client token fallback으로 읽는다. production 빌드는 proxy URL 또는 client token이 없으면 실패한다. `.env.local`, `.ait`, `dist`는 Git에서 제외된다.

로컬 브라우저 Origin은 운영 프록시 allowlist에 없으므로 실제 학교 검색은 QR/허용 Origin에서 확인한다. 로컬 UI 확인에는 단위·렌더 테스트 또는 명시적 체험 급식을 사용한다.

## 개발과 검증

```sh
npm ci
npm test
npm run test:release
npm run typecheck
npm run build:web
npm run verify:web
npx ait --help
npx ait build --help
npm run build:ait
npm run verify:release
```

Apps in Toss SDK는 stable `3.3.0`, TDS 패키지는 함께 `2.5.1`을 사용한다. Vite가 먼저 `dist`를 만들고 SDK 3 CLI가 `nyam-levelup.ait`을 만든다. 자동 migrate는 실행하지 않는다.

## 데이터와 안전

공식 `Storage`의 `nyam-toss:state:v2` 한 개를 새 원본으로 사용한다. v1 profile/progress/meal-record/cache를 읽어 v2를 먼저 저장하며 기존 key는 삭제하지 않는다. 손상된 값은 기본 상태로 복구하고 명시적인 삭제 확인 뒤에만 `Storage.clearItems()`를 호출한다.

XP identity는 `날짜|정규화한 메뉴 이름`이다. 기록 수정은 기존 identity를 교체하고 일일 50 XP cap을 최종 상태로 다시 계산한다. 체험 급식은 record, XP, cache 어느 것도 저장하지 않는다.

1~7단계는 main의 검증된 캐릭터를 512px WebP로 최적화했다. 8~12단계는 논리 단계와 제목을 유지하되, 검증된 원본이 없으므로 접근 가능한 `그림 준비 중` placeholder를 사용한다.
