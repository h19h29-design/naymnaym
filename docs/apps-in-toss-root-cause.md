# Apps in Toss Lite v2 출시 상태·장애 조사

조사 시각: 2026-09-04 (Asia/Seoul)

이 문서는 코드 변경 전 출시 상태 조사와 이후 백엔드 복구 시도의 증거를
구분해 기록한다. 후속 콘솔 조사로 확인한 값과 아직 확인하지 못한 값을
아래에서 명시적으로 구분한다.

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
| `apps-in-toss/granite.config.ts` | `appName`과 아이콘을 환경변수로 강제하고 displayName은 `급식레벨업`, 권한은 빈 배열이다. | 확인된 immutable appName `nyam-levelup`을 사용하고 실제 아이콘은 별도로 대조한다. |
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
  후속 콘솔 조사로 immutable appName이 `nyam-levelup`임을 확인했으므로 두
  origin은 현재 콘솔 identity와 일치한다.
- release verifier도 `nyam-levelup`을 `PRODUCTION_CONSOLE_IDENTITY`로
  하드코딩한다. identity 자체는 확인됐지만 환경변수 기반 검증으로 바꿔야
  다른 mini-app에 잘못 재사용되는 것을 막을 수 있다.
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

후속 콘솔 조사에서 다음 identity는 확인됐다.

- immutable appName: `nyam-levelup`
- live Origin: `https://nyam-levelup.apps.tossmini.com`
- QR/private Origin: `https://nyam-levelup.private-apps.tossmini.com`

따라서 이 세 값은 더 이상 추정이 아니다. 출시 중 bundle과 Git commit의
대응, entry path, 아이콘·썸네일의 파일 동일성은 별도 검증이 필요하다.

초기 조사에서는 immutable appName을 확인하지 않은 상태에서 Git의
`nyam-levelup`을 사용해 live/QR 주소를 추측하지 않았다. 후속 조사로 두
Origin은 확인됐지만 출시본/QR의 safe response, preflight, WebView UI 상태와
QR/live 차이는 아직 확보하지 못했다.
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

후속 콘솔 조사로 hard-coded default origin 두 개가 정확함을 확인했다.
Supabase secret의 존재 여부는 여전히 확인하지 못했으며, 비활성 프로젝트는
더 이상 운영 backend로 사용하지 않는다.

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

`npx --yes deno test supabase/functions/neis-proxy`는 standalone server
2개를 포함한 38개 테스트가 모두
통과했고 runtime source lint, type check, formatting, `git diff --check`도
통과했다. CORS default와 function secret은 변경하지 않았고 배포도 하지
않았다.

## NAS replacement architecture

Supabase free-project 활성 한도에 다른 서비스를 종속시키지 않기 위해 NEIS
proxy만 기존 NAS로 이동한다. 이 변경은 DB, volume, 계정, Toss console을
추가하거나 수정하지 않는다.

확인된 운영 입력:

- DSM `7.4.1-90080`, Docker `24.0.2`, Compose `2.20.1`
- 기존 ContainerManager는 실행 상태를 그대로 사용하며 package 단위의
  stop/start/restart를 호출하지 않음
- 기존 container 78개와 분리된 Compose project `neis-proxy`
- container `8000/tcp`를 host `127.0.0.1:18787`에만 bind
- public endpoint: `https://neis.h19h19.synology.me`
- DSM wildcard DNS/certificate가 해당 host를 포함
- secret은 NAS의 mode-600 전용 env file로만 전달
- json-file log rotation: `max-size=10m`, `max-file=3`

배포 전 read-only preflight에서 host port `18787`, Compose project 이름,
application path, secret file, public reverse-proxy host가 모두 사용되지 않은
상태임을 확인했다. DSM 설치 UI와 `SYNO.API.Info`를 조사해 지원 API가
`SYNO.Core.AppPortal.ReverseProxy` version 1이고, create schema가 기존 list
entry와 같은 `entry` object임을 확인했다. raw nginx/system config는 수정하지
않는다.

standalone server는 기존 `createHandler`를 그대로 사용한다. unauthenticated
surface는 `GET /health`의 `{ "ok": true }`뿐이고, `POST /`와 `OPTIONS /`는 기존
정확한 Origin, client token, body size, action/payload validation을 모두 거친다.
그 밖의 path는 404, `/health`의 다른 method는 405다.

container는 official `denoland/deno:alpine-2.9.6` multi-architecture image를
immutable digest로 pin한다. runtime은 UID/GID 1000, read-only root filesystem,
all Linux capabilities dropped, `no-new-privileges`, 16 MiB tmpfs로 실행한다.
Deno 권한도 지정한 세 환경변수와 `0.0.0.0:8000`,
`open.neis.go.kr:443` network access만 허용한다. 로컬 container preflight에서
health 200, runtime UID 1000, read-only/cap-drop/no-new-privileges,
`127.0.0.1:18787` bind와 wrong-Origin 403을 확인했다.

남는 위험은 client token이 앱 bundle에서 추출 가능한 abuse 억제용 값일 뿐
사용자 인증 수단이 아니라는 점, proxy 자체에 별도 IP rate limit이 없다는
점, 단일 NAS와 DSM reverse proxy가 장애 지점이라는 점이다. NEIS의 429는
재시도하지 않고 전달되며 Docker log rotation과 최소 권한으로 영향 범위를
제한한다. 필요 시 DSM/edge 계층 rate limit은 실제 abuse 지표를 근거로
추가한다.

### NAS 배포 결과

로컬 구현 commit `c815522afa0f32570aade2bc45d50d38e87290b4`를 먼저
생성한 뒤 그 commit의 runtime 파일만 NAS application path에 전송했다.
기존 NEIS key와 새 client token은 로컬 mode-600 env file을 거쳐 stdin으로
전송했고 NAS 전용 env file을 `root:root`, mode `600`으로 생성했다. 값은
명령행, 출력, 문서, Git, container log에 기록하지 않았다.

Compose는 image를
`local/neis-proxy:c815522afa0f32570aade2bc45d50d38e87290b4`로 tag하고
새 project `neis-proxy`만 `up --detach --build`했다. 기존 container 수는
78개에서 새 container 하나를 포함한 79개가 됐다. ContainerManager package의
stop/start/restart는 호출하지 않았다.

DSM reverse proxy는 지원 API `SYNO.Core.AppPortal.ReverseProxy.create`로 한
건만 만들었다. 생성 결과는 `success=true`, `httpd_restart=true`였으며 최종
entry는 다음과 같다.

- UUID: `4cd66938-e026-4ba0-ad19-0c0503a49771`
- frontend: HTTPS `neis.h19h19.synology.me:443`, HSTS enabled
- backend: HTTP `127.0.0.1:18787`
- connect/read/send timeout: 60초
- custom header: 없음

rule reload 직후 최초 public health 요청 한 번은 HTTP 200의 non-JSON body를
받았다. 이후 응답은 nginx를 통해 HTTP 200,
`application/json; charset=utf-8`, 정확히 `{ "ok": true }`였고 같은 현상이
재현되지 않았다. 이는 reload 중의 일시 상태라는 추론이며 원시 응답은
보존하지 않았다.

secret-safe smoke 결과:

```text
PASS: health
PASS: both verified OPTIONS origins
PASS: wrong Origin denied
PASS: school search
PASS: June 2026 meal with allergens, calories, and nutrition
```

학교 검색은 `등촌고등학교`, office code `B10`, school code `7010700`을
확인했다. 급식은 `20260601`의 실제 메뉴, 알레르기 번호, calorie, nutrition을
NAS proxy를 통해 확인했다. 기본 TLS 검증을 끄는 option은 사용하지 않았다.

container에는 두 번의 최종 smoke 요청으로 JSON log 10건만 남았다. 모든
line이 허용된
`requestId`, `action`, `status`, `durationMs`, `safeReason`,
`neisResultCode` key의 부분집합이었고 URL, payload, token/key 이름, 학교명,
학교 코드는 없었다. 결과는 OPTIONS 204 네 건, wrong-Origin 403
`origin_denied` 두 건, `searchSchools` 200 `INFO-000` 두 건, `fetchMeals` 200
`INFO-000` 두 건이다.

### 초등학교 및 7일 범위 계약 확장

NEIS 공식 `급식식단정보` Open API metadata를 read-only로 조회한 결과,
`MLSV_FROM_YMD`와 `MLSV_TO_YMD`는 선택 request parameter이고
`MLSV_YMD`는 실제 급식일자 response field다. 공식 `학교기본정보` metadata도
`SCHUL_KND_SC_NM`을 선택 filter와 response field로 제공한다. 따라서 range를
단일 upstream request로 보내고 각 row의 `MLSV_YMD`를 사용하는 구현은 공식
계약에 근거한다.

commit `3eb443799258604c765cd3f80b8eb230aace558a`에서 다음을 구현했다.

- `SchoolType`을 `elementary | middle | high`로 확장하고 초등학교 filter를
  NEIS의 `초등학교` 값으로 mapping한다.
- 기존 `fetchMeals`는 유지하고 `fetchMealsRange`의
  `{officeCode, schoolCode, fromDate, toDate}`를 추가한다.
- range는 UTC calendar 기준 양 끝을 포함해 1~7일만 허용한다. 역순, 실제로
  존재하지 않는 날짜, 8일 이상, extra key는 upstream 호출 전에 거부한다.
- range는 `MLSV_FROM_YMD`와 `MLSV_TO_YMD`를 이용한 upstream 한 번만
  사용한다. DB, cache, 날짜별 fan-out은 추가하지 않았다.
- range의 `INFO-200` 또는 정상 empty rows는 HTTP 200 `{ok:true,data:[]}`다.
  기존 단일 날짜 no-data의 HTTP 404 `NO_DATA`는 바꾸지 않았다.

실제 NEIS read-only 확인에서는 `서울등촌초등학교`가 office code `B10`,
school code `7081436`으로 검색됐고 `20260601`~`20260607` 한 번의 range
요청은 실제 row 날짜 `20260601`, `20260602`, `20260604`, `20260605`를
반환했다.

같은 commit SHA로 전용 image를 rebuild하고 `neis-proxy-proxy-1` container
하나만 recreate했다. 기존 DSM reverse-proxy rule과 ContainerManager package는
변경하지 않았다. container 내부 runtime source 6개의 hash는 해당 commit과
모두 일치했고 기존 mode-600 환경 파일도 변경되지 않았다. public TLS smoke는
다음을 통과했다.

```text
PASS: health
PASS: both verified OPTIONS origins
PASS: wrong Origin denied
PASS: school search
PASS: elementary school search
PASS: June 2026 meal with allergens, calories, and nutrition
PASS: seven-day elementary meal range with actual NEIS dates
```

최종 safe log는 `fetchMealsRange` 200 `INFO-000` 한 건을 포함해 모두 허용된
diagnostic key만 사용했고 URL, environment key 이름, 학교명과 학교 코드는
포함하지 않았다.

### Rollback

rollback은 새 리소스 두 개만 대상으로 한다. 먼저 위 UUID가 여전히 target
host의 단일 rule인지 list API로 확인한 뒤
`SYNO.Core.AppPortal.ReverseProxy.delete` version 1에
`uuids=["4cd66938-e026-4ba0-ad19-0c0503a49771"]`를 전달한다. 그 다음 같은
commit SHA를 `NEIS_PROXY_IMAGE_TAG`로 설정하고 해당 compose file에
`--project-name neis-proxy down`을 실행한다. 이는 새 container와 project
network만 내리며 다른 container나 ContainerManager package를 건드리지
않는다. application 파일, image, mode-600 secret은 문제 분석과 빠른 재배포를
위해 기본 rollback에서 삭제하지 않는다.

## 의존 순서

1. 현재 출시본 또는 QR에서 실패 요청 하나를 재현해 origin, secret 없는
   request URL, status/error class, safe response, OPTIONS, UI 상태와 function
   log를 묶는다. 이 증거로 장애 분류를 확정한다.
2. NAS Compose project와 전용 DSM reverse-proxy rule만 배포하고 local/public
   health, 두 Origin의 OPTIONS, wrong-Origin 403, 실제 학교·급식을 검증한다.
3. 실제 등촌고등학교 검색과 실제 급식 반환 후에만 client scaffold와 기존
   Storage migration을 연결한다.
4. 오늘/주간/설정 UI를 4개 경로와 3개 탭으로 줄이고 최신 12단계 정책을
   적용한다. 8~12단계 art는 별도 확인 없이는 생성하거나 꾸며내지 않는다.
5. unit/type/web/release gate 뒤 기존 mini-app에만 test bundle을 올리고 iOS,
   Android QR 및 live origin을 각각 확인한다. 검토 요청과 출시는 누르지
   않는다.

## Phase 3 client resolution

client는 SDK 3.3.0의 `apps-in-toss.config.ts`와 `webBundleDir=dist`로 수동
migration했다. 운영 endpoint는 `VITE_NEIS_PROXY_URL` 하나로 분리했고,
client token은 v2 환경 이름을 우선하며 과거 anon 이름은 한 버전 fallback으로만
읽는다. UI는 오류를 sample로 덮지 않고 live, cache, no-data, backend,
network, Origin, rate-limit 상태를 분리한다. 따라서 과거 inactive Supabase를
다시 깨우는 heartbeat나 새 유료 리소스 없이 현재 NAS proxy를 사용할 수 있고,
추후 승인된 backend로도 환경 값 하나만 바꿔 이전할 수 있다.

## Phase 4 release candidate

두 축 코드 리뷰 뒤 legacy meal status 보존, 손상 cache 검증, canonical meal
identity, 월요일~일요일 주간 범위, 학교 지역·학교급 표시, 설정의 앱 정보,
성공 응답 runtime schema 검증, 최신 cache fallback, live proxy의 sample 거부,
고정 WebP hash 검증을 추가했다. 최종 app test 32개와 release test 5개가
통과했다.

2026-09-05 00:14 KST 기존 workspace 62825 / mini-app 57196에 SDK 3.3.0
bundle을 한 건 등록했다.

- console version: `20260905-15`
- console status: `검토 필요`
- deployment ID: `01a06cfb-ab5f-705d-b1b6-815f815f6cb0`
- test scheme:
  `intoss-private://nyam-levelup?_deploymentId=01a06cfb-ab5f-705d-b1b6-815f815f6cb0&host=appsInTossHost`
- 업로드 직전 artifact: 660,958 bytes, SHA-256
  `60f3236a6ce99facd6094565d0b55b875b1642c82f7f96625971f1140328bd42`

등록 후 QR 발급과 정확한 appName을 확인했다. `검토 요청`과 `출시하기`는
누르지 않았다. 현재 연결된 물리 iOS 기기가 없고 Android ADB도 사용할 수
없어 QR WebView의 학교 검색, 오늘/주간, 기록·XP 재실행 보존, 뒤로가기는
완료 판정하지 않는다. 일반 브라우저에서 private host를 직접 여는 요청은
HTTP 403이며 Toss WebView를 대체할 수 없다.

공개 privacy/support 페이지는 HTTP 200이었지만 native 전용 사진·부모 연결
문구를 플랫폼 구분 없이 표시하는 정합성 문제가 확인됐다. feature branch의
`marketing-site/dist/` 원본을 앱인토스 Lite v2와 iOS·Android 기능을 명확히
구분하도록 수정하고, 같은 세 페이지를 `gh-pages` commit
`1ef929c16d8870639c75bfe8834477eb531d9de0`으로 배포했다. privacy, support,
data-safety URL은 모두 HTTP 200이고 새 Lite v2 문구가 표시되며 과거
`냠냠레벨업`/`1.0 공개 배포 후보` 표시는 없다. 실제 QR WebView에서 외부
페이지가 열리는지는 물리 기기 테스트로 남는다.

후속 검증 과정에서 CLI가 ignored `.ait`를 재생성했지만, 업로드 deployment
ID와 생성 시각을 이용해 SDK writer의 동일 입력으로 artifact를 복원했다.
현재 `apps-in-toss/nyam-levelup.ait`은 위 업로드 직전 크기와 SHA-256에 다시
정확히 일치하며 `verify:release`를 통과한다.

### iOS QR 확인과 검토 요청

2026-09-05 사용자가 `20260905-15` QR을 iOS Toss 앱에서 열어 앱 실행과 초기
화면 표시를 확인했다. 같은 시점의 NAS container safe log 최근 10분 요약은
`fetchMeals` 404 두 건과 `fetchMealsRange` 200 한 건이었다. 따라서 QR
WebView가 보호된 NAS endpoint까지 도달하고 주간 급식 응답을 받은 사실은
확인했다. 학교 재검색, 기록 저장, 재실행 보존, 뒤로가기는 항목별 증거를
확보하지 않았으며 Android QR도 미검증이다.

사용자는 Android 미검증 상태를 명시적으로 수용하고 `20260905-15` 검토 요청
제출을 승인했다. 2026-09-05 09:55 KST 콘솔에 출시 노트를 입력해 제출했고,
`요청이 완료되었어요` 알림과 해당 버전의 `검토 중` 상태를 직접 확인했다.
콘솔 안내상 결과는 영업일 3일 내 이메일로 전달된다. `출시하기`는 실행하지
않았다.
