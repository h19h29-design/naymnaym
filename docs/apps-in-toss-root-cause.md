# Apps in Toss Lite v2 출시 상태·장애 조사

조사 시각: 2026-09-04 (Asia/Seoul)

이 문서는 코드 변경 전 출시 상태 조사와 이후 백엔드 복구 시도의 증거를
구분해 기록한다. 앱인토스 콘솔 인증이 필요한 값은 아직 확정하지 않았다.

## Git 기준선

다음 명령을 현재 작업 트리에서 실행했다.

```text
git fetch --all --prune
git status --short
git rev-parse origin/main
git rev-parse origin/codex/apps-in-toss-mvp
git merge-base origin/main origin/codex/apps-in-toss-mvp
git rev-list --left-right --count origin/main...origin/codex/apps-in-toss-mvp
```

- 작업 브랜치: `codex/apps-in-toss-lite-v2`
- 작업 트리: clean (`git status --short` 출력 없음)
- `HEAD`와 `origin/main`: `6789f88ec2d2df18edf44897afc7ce9211055cc1`
  (`chore: prepare iOS 1.2 build 34`)
- `origin/codex/apps-in-toss-mvp`:
  `2f6591b696cbbe22a19b4c9b52102574e1e43df2`
  (`fix: clarify rate-limited next meal retry`)
- merge-base: `2dbdc61567f18d31b8b445c9430337a6baabd67a`
- 분기 후 커밋 수: main 쪽 156개, MVP 쪽 61개
- merge-base 기준 MVP 변경: 107 files, 40,285 insertions, 49 deletions
- 두 브랜치가 분기 후 함께 수정한 경로는 `marketing-site/README.md`와
  `marketing-site/dist/` 아래 6개 HTML뿐이다. 이 경로들은 선택 복사에서
  제외해야 최신 main의 배포 페이지를 덮어쓰지 않는다.
- `apps-in-toss/`, `supabase/functions/neis-proxy/`,
  `supabase/functions/_shared/neis-contract/`는 main에 없어서 파일 단위로
  가져올 수 있다. 요구사항에 적힌 `packages/neis-contract/`는 MVP 브랜치에
  존재하지 않는다. 실제 로컬 패키지는
  `supabase/functions/_shared/neis-contract/`이고 `apps-in-toss/package.json`이
  `file:../supabase/functions/_shared/neis-contract`로 참조한다.
- Git 추적 파일과 `/Users/mac-mini/Documents/냠냠` 아래에서 `.ait` 파일을
  찾지 못했다. 따라서 로컬 산출물로 현재 출시 번들을 특정할 수 없다.

## 선택 재사용 후보와 선행 조건

| 재사용 후보 | 검증된 현재 상태 | 가져오기 전 필요한 변경 |
| --- | --- | --- |
| `apps-in-toss/package.json`, `package-lock.json`, `index.html`, `tsconfig*.json`, `vite.config.ts`, `vitest.setup.ts` | 독립 Granite/Vite/React 앱과 요청된 빌드·검증 스크립트가 있다. | SDK stable 버전과 마이그레이션 문서를 먼저 확인하고 lockfile을 그 결정 뒤 갱신한다. |
| `apps-in-toss/granite.config.ts` | `appName`과 아이콘을 환경변수로 강제하고 displayName은 `급식레벨업`, 권한은 빈 배열이다. | 콘솔에서 immutable appName과 실제 아이콘을 확인한 뒤에만 운영 빌드에 사용한다. |
| `apps-in-toss/src/services/storage.ts` | 운영에서는 Apps in Toss `Storage`; 개발에서만 `localStorage` fallback을 쓴다. | 현재 Storage API가 선택한 SDK 버전에서 호환되는지 확인한다. |
| `apps-in-toss/src/services/repository.ts` 및 테스트 | 기존 `nyam-toss:*:v1` 프로필·진행·기록·캐시 키, 직렬화, 삭제 경합 보호, pending feedback 복구가 있다. | `schemaVersion`, 초등학교, 최신 단일 `totalXP` 재계산 마이그레이션을 추가하고 성공 전 기존 키를 삭제하지 않는다. 기존 validation 실패 시 즉시 key를 지우는 동작도 마이그레이션 요구와 함께 재검토한다. |
| `supabase/functions/_shared/neis-contract/`, `apps-in-toss/src/services/neisClient.ts`, `supabase/functions/neis-proxy/` 및 테스트 | 클라이언트/함수 공유 계약, text/plain POST, origin/token 경계, NEIS 정규화와 오류 테스트가 있다. | 계약을 먼저 확장한 뒤 프록시와 클라이언트를 같은 순서로 갱신한다. 현재 계약은 중·고교와 단일 날짜만 지원한다. |
| `apps-in-toss/src/features/onboarding/` | 실제 학교 검색 UI와 WebView/iOS 관련 회귀 수정 이력이 있다. | 초등학교, 선택 별명, 새 오류 상태를 추가하고 현재 계약 변경 뒤 연결한다. |
| `apps-in-toss/src/features/today/`, `components/Meal*`, `domain/allergy.ts`, `domain/records.ts` | 실제 급식, 명시적 demo, 알레르기와 식사 기록의 테스트 가능한 흐름이 있다. | 최신 main의 정책으로 교체하고 알레르기 메뉴의 한 입 도전을 잠근다. |
| `apps-in-toss/src/features/meals/MealSchedulePage.tsx` | 일간·주간·월간을 한 파일에서 제공한다. | `/week`의 7일 범위만 남기고 proxy range 계약 뒤 연결한다. |
| `apps-in-toss/scripts/verify-release.mjs` 및 테스트 | `.ait` 구조·크기·secret·에셋 검증이 있다. | 하드코딩된 과거 console identity를 제거하고 직접 확인한 콘솔 값으로 검증한다. |
| `apps-in-toss/release-assets/` | 아이콘, 썸네일, 검수 이미지가 있다. | 콘솔의 현재 이미지와 일치 여부를 먼저 확인한다. 문구와 화면은 7단계·과거 탭 구조라 그대로 재사용하지 않는다. |

## 최신 main이 우선하는 제품 계약

- `README.md`: 초·중·고 지원, 실제 실패를 샘플로 대체하지 않는 규칙,
  알레르기 안전 문구를 명시한다.
- `NaymNaymLevelUp/Services/NEISClient.swift`와
  `NaymNaymLevelUp/Services/MealService.swift`: NEIS 요청/응답 처리와 live,
  cached, no-meal, error, explicit-demo 경계를 제공한다.
- `NaymNaymLevelUp/Resources/RebuildContracts/growth-policy.json`과
  `NaymNaymLevelUp/Rebuild/Growth/GrowthDomain.swift`: 12단계 threshold는
  `0, 80, 180, 320, 500, 720, 1000, 1300, 1650, 2050, 2500, 3000`이다.
- `NaymNaymLevelUp/Resources/RebuildContracts/xp-policy.json`: award identity는
  `{date}|{normalizedMenuName}`이고 상태 변경은 추가 XP를 주지 않는다.
- `docs/CHARACTER_ASSET_MANIFEST.md`: 저장소에서 검증된 캐릭터 이미지는
  1~7단계뿐이며 8~12단계는 native의 `그림 준비 중` placeholder다. 따라서
  "최신 12단계 이미지"가 이미 존재한다고 전제하면 안 된다.
- `scripts/smoke-neis-live.sh`: 등촌고등학교/202606 실제 학교·급식 검증
  절차를 제공하지만, 직접 NEIS key를 사용하는 native smoke이므로 프록시
  smoke로 그대로 간주할 수는 없다.

## 확인된 구형 구현 위험

- 라우트는 `/onboarding`, `/today`, `/meals`, `/growth`, `/collection`,
  `/settings`로, Lite v2 최대 4개 경로보다 많다.
- `SchoolType`과 profile validation은 `middle | high`만 허용한다.
- 성장 정책과 bundled growth PNG는 7단계다.
- 환경변수 이름이 `VITE_SUPABASE_ANON_KEY`이고 클라이언트의 옵션 이름도
  `anonKey`지만 실제 용도는 JSON body의 `clientToken`이다.
- proxy upstream timeout은 1,800 ms이고 재시도가 없으며 로그에는
  `safeReason`과 NEIS result code가 없다.
- proxy 계약은 `fetchMeals` 단일 날짜만 지원하고 최대 7일 range 요청이
  없다.
- origin 설정에는 `nyam-levelup` 두 origin이 기본값으로 내장돼 있다.
  이 값은 Git 커밋의 주장일 뿐 이번 조사에서 콘솔로 재확인하지 못했다.
- release verifier도 `nyam-levelup`을 `PRODUCTION_CONSOLE_IDENTITY`로
  하드코딩한다. 이것도 현재 콘솔의 직접 증거로 취급하지 않는다.
- MVP의 tracked 파일 약 18.5 MB 중 public/release asset이 약 17.1 MB다.
  화면 축소와 최신 에셋 선별을 먼저 해야 한다.

## 앱인토스 콘솔과 현재 오류 재현

Chrome 프로필 `화영`의 탭 `2007622603`에서
`https://apps-in-toss.toss.im/`를 열었으나 Toss Business 로그인 화면으로
이동했다. 계정 정보 입력이나 설정 변경은 하지 않았고 로그인 인계용으로
탭을 유지했다.

인증 전에는 workspace `62825` / mini-app `57196`의 다음 값을 직접 확인할
수 없었다.

- 현재 display name과 immutable appName
- 출시 중 bundle version과 Git/bundle 대응 증거
- 등록된 기능 entry path
- QR 및 live scheme/origin
- 현재 아이콘과 썸네일
- 최신 승인본·반려본과 사유

immutable appName을 확인하지 않은 상태에서 Git의 `nyam-levelup`을 사용해
live/QR 주소를 추측하지 않았다. 따라서 출시본/QR의 실제 Origin, safe
response, preflight, WebView UI 상태와 QR/live 차이는 아직 확보하지 못했다.
다만 아래의 production endpoint 직접 재현과 Supabase 관리 API 조사로
`INACTIVE` 상태가 현재 연결 장애의 원인임은 별도로 확인했다. CORS, secret,
client token, 1.8초 timeout은 활성화 이후 확인해야 할 2차 위험이다.

## Supabase 백엔드 장애 재현과 복구 시도

다음 명령은 secret이나 token 값 없이 production Edge Function의 학교 검색
경로에 연결을 시도하고, DNS/gateway 도달 여부만 판정한다. 유효한 token을
넣지 않았으므로 프로젝트가 활성 상태일 때 함수 성공 여부를 검증하는
smoke가 아니라 `BACKEND_UNAVAILABLE` 재현용이다.

```sh
probe_body=$(mktemp)
probe_status=$(curl --silent --show-error --max-time 12 \
  --output "$probe_body" --write-out '%{http_code}' \
  --request POST \
  'https://xblswzqzjfchtcnfycya.supabase.co/functions/v1/neis-proxy' \
  --header 'content-type: application/json' \
  --data '{"clientToken":"","request":{"action":"searchSchools","payload":{"keyword":"등촌고등학교"}}}')
probe_rc=$?
printf 'curl_exit=%s http_status=%s response_bytes=%s\n' \
  "$probe_rc" "$probe_status" "$(wc -c < "$probe_body" | tr -d ' ')"
if [ "$probe_rc" -ne 0 ] || [ "$probe_status" = 000 ]; then exit 1; fi
```

실행 결과는 `curl_exit=6`, `http_status=000`, `response_bytes=0`이었고 DNS에서
끝났기 때문에 CORS, token, 함수 본문, NEIS upstream까지 도달하지 않았다.
같은 시점의 Supabase project 조회 결과는 다음과 같다.

- project: `nyam-levelup` (`xblswzqzjfchtcnfycya`)
- region: `ap-northeast-2`
- status: `INACTIVE`
- 분류: `BACKEND_UNAVAILABLE`

요구사항에 따라 기존 무료 프로젝트의 cost-free restore를 요청했지만,
조직 구성원에게 허용된 active free project 수가 이미 한도에 도달해
Supabase가 요청을 거부했다. 복구하려면 다른 active project를 pause/delete
하거나 요금제를 변경해야 한다. 어느 작업도 승인 범위가 아니므로 수행하지
않았고 production은 여전히 `INACTIVE`다. 다른 project, 데이터, 설정, 함수,
secret은 변경하거나 삭제하지 않았다.

## 배포 함수와 로그 조사

Supabase 관리 API에서 확인한 함수 상태는 다음과 같다.

- slug: `neis-proxy`
- deployed version: `10`
- function status: `ACTIVE` (project 자체는 `INACTIVE`)
- `verify_jwt`: `false`
- entry files: `index.ts`, `handler.ts`, `neis-normalizer.ts`,
  `origin-config.ts`
- 네 파일 모두 줄바꿈을 정규화한 내용이
  `origin/codex/apps-in-toss-mvp`의 같은 파일과 정확히 일치했다.
- 최근 Edge Function log 조회 결과는 0건이었다. DNS에서 종료된 재현 요청은
  invocation log를 만들지 않았다.

현재 연결에 노출된 Supabase MCP에는 secret 목록 조회 기능이 없고 로컬
Supabase CLI도 설치돼 있지 않다. 프로젝트가 비활성이라 runtime의
`NOT_CONFIGURED` 응답으로도 확인할 수 없었다. 따라서 다음은 값이 아니라
**존재 여부도 아직 미확인**이다.

- `NEIS_API_KEY`
- `NEIS_ALLOWED_ORIGINS`
- `NEIS_CLIENT_TOKEN`

immutable appName을 콘솔에서 확인하기 전에는 hard-coded default origin이
맞는지 판정하거나 CORS 설정을 바꾸지 않는다.

## 직접 NEIS 기준 데이터 확인

worktree에는 secret 파일이 없어서 `./scripts/smoke-neis-live.sh`가
`Config.xcconfig is missing`으로 중단됐다. 이후 기존 600 권한 설정 파일을
읽는 main checkout의 동일 스크립트를 실행했다. secret 값은 명령행이나
출력에 넣지 않았다.

```text
PASS: schoolInfo resolved 등촌고등학교 officeCode=B10 schoolCode=7010700
PASS: mealServiceDietInfo returned 19 lunch rows for 등촌고등학교 202606
PASS: first meal row includes MLSV_YMD, DDISH_NM, CAL_INFO, NTR_INFO
```

따라서 조사 시점의 NEIS upstream과 기준 데이터는 정상이다. 이 결과는
비활성 Supabase proxy를 통과한 검증이 아니므로 production backend 복구를
의미하지 않는다.

## 로컬 프록시 hardening

배포하지 않은 worktree 구현에서 다음 회귀 테스트를 먼저 실패시킨 뒤
수정했다.

- upstream timeout: 1,800 ms에서 8,000 ms로 조정
- timeout, network failure, transient 5xx: 최대 1회만 재시도
- HTTP/NEIS 429: 재시도하지 않음
- 안전 로그: `requestId`, `action`, `status`, `durationMs`, `safeReason`,
  `neisResultCode` 외의 payload, URL, key, token을 기록하지 않음
- `upstream_timeout`, `upstream_http_error`, `neis_no_data`,
  `neis_rate_limited`, `response_parse_error` 등을 구분

`npx --yes deno test supabase/functions/neis-proxy`는 36개 테스트가 모두
통과했고 runtime source lint, type check, formatting, `git diff --check`도
통과했다. CORS default와 function secret은 변경하지 않았고 배포도 하지
않았다.

## 의존 순서

1. 보존된 Toss Business 탭에서 사용자가 로그인한 뒤 workspace `62825` /
   mini-app `57196`의 identity, 버전, entry, scheme, 이미지, 심사 이력을
   읽기 전용으로 캡처한다.
2. 확인한 immutable appName으로 QR/live origin을 확정한다.
3. 현재 출시본 또는 QR에서 실패 요청 하나를 재현해 origin, secret 없는
   request URL, status/error class, safe response, OPTIONS, UI 상태와 function
   log를 묶는다. 이 증거로 장애 분류를 확정한다.
4. 승인받은 active project 정리 또는 요금제 결정 뒤 `nyam-levelup`을
   복구한다. 그 다음 secret **존재 여부**와 실제 Origin을 확인하고 로컬
   hardening을 배포한 뒤 proxy smoke를 실행한다.
5. 실제 등촌고등학교 검색과 실제 급식 반환 후에만 client scaffold와 기존
   Storage migration을 연결한다.
6. 오늘/주간/설정 UI를 4개 경로와 3개 탭으로 줄이고 최신 12단계 정책을
   적용한다. 8~12단계 art는 별도 확인 없이는 생성하거나 꾸며내지 않는다.
7. unit/type/web/release gate 뒤 기존 mini-app에만 test bundle을 올리고 iOS,
   Android QR 및 live origin을 각각 확인한다. 검토 요청과 출시는 누르지
   않는다.
