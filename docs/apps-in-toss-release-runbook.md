# 냠냠레벨업 앱인토스 무료 운영·검수 런북

이 문서는 토스 미니앱 MVP만 다룹니다. 기존 iOS/Android 앱의 사진, 부모 연결, 서버 동기화 고지는 그대로 유지하며, 이를 미니앱에 배포하거나 사용하지 않습니다. 미니앱은 토스 `Storage`와 NEIS 요청을 중계하는 `neis-proxy` Edge Function을 사용합니다. 앱인토스 검수 또는 출시는 토스의 판단이며 이 체크리스트가 승인을 보장하지는 않습니다.

## 운영 경계와 공개 정보

- 로컬 저장: 별명, 선택 학교, 알레르기, 식사 기록, XP, 레벨, 급식 캐시는 토스 `Storage`에 저장합니다. 토스 앱/미니앱 삭제, 토스 저장소 삭제, 기기 변경 시 사라질 수 있으며 설정의 **내 데이터 삭제**로 지웁니다.
- Edge·NEIS 처리: 학교 검색어 또는 선택 학교 코드와 날짜가 급식 조회 목적의 `neis-proxy`와 NEIS API로 전달됩니다. Origin, IP 주소, User-Agent, 헤더 등 통상적인 요청 메타데이터와 Supabase 호출·로그 메타데이터도 제공자 운영 과정에서 처리될 수 있습니다. 함수 애플리케이션 로그는 요청 ID, 작업 종류, 상태, 처리 시간만 남기며 요청 본문과 키는 남기지 않습니다.
- Supabase 경계: 미니앱 코드는 **Supabase DB, Auth 사용자, Storage, Realtime에 사용자 기록을 작성하지 않습니다.** Edge Function과 비밀 설정은 사용합니다. 이 문장은 제공자 플랫폼의 일반적 호출/보안/로그 처리를 부정하는 뜻이 아닙니다.
- 보관·처리 위치: 실제 Supabase 프로젝트 지역, 호출·로그 보관 설정, Supabase/NEIS의 보관 기간 및 처리 위치는 아직 출시 구성으로 확정하지 않았습니다. Task 11 제출 전 프로젝트 설정과 제공자 정책을 확인하고, 정책 페이지·검수 자료에 반영합니다. 보장되지 않은 정확한 보관 기간이나 위치를 쓰지 않습니다.
- 클라이언트 키: `VITE_SUPABASE_ANON_KEY`에는 브라우저 공개용 기존 `anon` 키만 사용합니다. iOS WebView에서 CORS 사전요청을 만들지 않도록 커스텀 인증 헤더 대신 JSON 본문의 `clientToken`으로 보내고, 함수가 `NEIS_CLIENT_TOKEN`과 직접 비교합니다. 이 공개 값은 사용자 인증이나 비밀키가 아닙니다. `service_role`와 `sb_secret_`는 금지입니다. [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets), [Supabase function authorization](https://supabase.com/docs/guides/functions/auth)
- 금지: 실제 키·콘솔 값, 유료 토스 기능, 자동 결제, 자동 요금제 업그레이드. 키·값·전체 origin 문자열이 보이는 화면을 검수 캡처나 이슈에 올리지 않습니다.

## 한 번만 준비할 설정

1. 로컬 전용 `apps-in-toss/.env`에 `AIT_APP_NAME`, `AIT_ICON_URL`, `VITE_NEIS_PROXY_URL`, `VITE_SUPABASE_ANON_KEY`의 실제 값을 넣습니다. `VITE_SUPABASE_ANON_KEY`는 브라우저 공개용 기존 `anon` 키를 사용합니다. 값은 각 콘솔의 해당 필드에서 복사하고, `.env`를 커밋하지 않습니다.
2. `VITE_NEIS_PROXY_URL`은 Supabase Dashboard **Edge Functions → neis-proxy**에서 확인한 함수 URL입니다. URL 형식과 함수 배포 절차는 [Supabase Edge Function 배포 문서](https://supabase.com/docs/guides/functions/deploy)를 따릅니다.
3. Supabase Dashboard **Edge Functions → Secrets**에 `NEIS_API_KEY`, `NEIS_ALLOWED_ORIGINS`, `NEIS_CLIENT_TOKEN`을 등록합니다. `NEIS_API_KEY`에는 NEIS 제공자 콘솔에서 발급·승인된 키를 직접 복사하고, `NEIS_CLIENT_TOKEN`은 로컬 `VITE_SUPABASE_ANON_KEY`와 같은 공개 값으로 맞춥니다. 어떤 값도 Git, 로그, QR 캡처에 넣지 않습니다. Secrets 변경은 재배포 없이 함수에서 사용할 수 있습니다. [Supabase secrets guide](https://supabase.com/docs/guides/functions/secrets)
4. `NEIS_ALLOWED_ORIGINS`에는 아래처럼 프로토콜·호스트만 쉼표로 연결하여 **정확히** 넣습니다. 끝 `/`, 와일드카드, 부분 도메인, 공백으로 된 별도 항목을 넣지 않습니다. `<appName>`은 `AIT_APP_NAME`의 실제 앱 이름으로 치환합니다.

   ```text
   https://<appName>.apps.tossmini.com,https://<appName>.private-apps.tossmini.com
   ```

   - 운영 origin: `https://<appName>.apps.tossmini.com`
   - 콘솔 QR 테스트(sandbox) origin: `https://<appName>.private-apps.tossmini.com`
   - 로컬 브라우저로 프런트엔드까지 확인할 때만 `http://localhost:5173`을 별도 항목으로 임시 추가하고, 출시 전 제거합니다.

   토스는 QR 테스트와 실제 서비스 환경의 CORS/네트워크 동작이 다를 수 있다고 안내하며, 위 두 origin을 각각 허용하도록 명시합니다. [앱인토스 미니앱 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html)

5. 함수 코드는 `supabase/functions/neis-proxy/`만 `verify_jwt=false`로 배포합니다. 배포 전후에 함수가 정확한 토스 Origin, `clientToken`, 4 KiB 본문 제한, `searchSchools`·`fetchMeals` 작업과 고정 필드만 허용하는지 테스트합니다. 토큰 누락·불일치, 허용되지 않은 Origin은 NEIS 호출 전에 403으로 거절되어야 합니다. 이 함수는 미니앱 사용자 레코드를 쓰지 않습니다. 배포 전에는 부모 동기화 함수, migrations, DB 테이블, Auth 사용자, Storage bucket, Realtime 채널을 이 미니앱 구성에 추가하지 않았는지 다시 확인합니다.

## 키 회전과 중단

### NEIS 키 회전

1. NEIS 제공자 콘솔에서 새 키를 발급하고 기존 키는 아직 철회하지 않습니다.
2. Supabase **Edge Functions → Secrets**에서 `NEIS_API_KEY`만 새 값으로 교체합니다. 값은 화면이나 명령 출력에 붙여 넣지 않습니다.
3. 허용된 QR origin에서 학교 검색과 급식 조회를 각각 한 번 실행하고, 함수 로그에서 상태와 오류 코드만 확인합니다. 키나 요청 본문을 기록하지 않습니다.
4. 성공을 확인한 뒤에만 NEIS 제공자 콘솔에서 기존 키를 철회합니다. 실패하면 새 키를 노출하지 말고 비밀 설정을 이전 상태로 되돌린 뒤 원인을 조사합니다.

### 무료 한도 접근 또는 이상 요청 시

1. 앱은 `RATE_LIMITED` 또는 서비스 제한 메시지를 표시하고 자동 결제·자동 업그레이드를 하지 않습니다. 실제 학교 조회는 샘플 급식으로 자동 대체하지 않습니다.
2. 즉시 NEIS 호출을 막아야 하면 지원되는 CLI로 `supabase secrets unset NEIS_ALLOWED_ORIGINS --project-ref <project-ref>`를 실행합니다. 현재 함수는 허용 origin이 없으면 NEIS를 호출하지 않고 `NOT_CONFIGURED`/503을 반환합니다. 허용된 origin에서 응답이 503이고 코드가 `NOT_CONFIGURED`인지 확인하되 키·요청 본문은 출력하거나 기록하지 않습니다. [Supabase secrets unset](https://supabase.com/docs/reference/cli/supabase-secrets-unset)
3. 계속 중단할 때는 프로젝트를 확인한 뒤 `neis-proxy`만 삭제/undeploy합니다. `supabase functions delete neis-proxy --project-ref <project-ref>`는 원격 함수만 삭제하고 로컬 소스는 지우지 않습니다. 프로젝트 전체를 삭제하거나 데이터 제품을 새로 켜지 않습니다. [Supabase functions delete](https://supabase.com/docs/reference/cli/supabase-functions-delete)
4. 재개할 때는 새 키와 정확한 두 토스 origin을 다시 설정하고 `neis-proxy`만 배포한 뒤 QR과 운영 환경을 다시 확인합니다.

## 사용량·무료 플랜 감시

- 매 검수 전과 출시 후 정기적으로 Supabase 조직 **Usage** 화면의 Edge Function Invocations, egress/compute 관련 지표와 함수 로그의 429·5xx를 확인합니다. 사용량 화면에서 기간과 대상 프로젝트를 선택할 수 있습니다. [Edge Function invocation usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)
- 무료 한도에 가까워지거나 예상하지 못한 증가가 있으면 먼저 위 중단 절차를 적용하고 요청을 조사합니다. 업그레이드 버튼, spend-cap 변경, 카드/결제 수단 추가, 유료 토스 기능 활성화는 이 MVP의 대응책이 아닙니다.
- 수치와 플랜 조건은 변경될 수 있으므로 런북에 고정하지 않습니다. 판단 시점의 Supabase Usage/가격 화면을 확인합니다. [Supabase pricing](https://supabase.com/pricing)
- 기능은 짧은 NEIS 중계만 수행하고 DB/Auth/Storage/Realtime을 사용하지 않습니다. 무료 운영을 위해 새 인프라나 사용자를 만들지 않습니다.

## 빌드와 release gate

`apps-in-toss/`에서 다음 순서로 실행합니다.

```bash
npm test
npm run typecheck
npm run build:web
npm run verify:web
AIT_APP_NAME=nyam-mvp AIT_ICON_URL=https://example.invalid/icon.png VITE_NEIS_PROXY_URL=https://example.invalid/functions/v1/neis-proxy VITE_SUPABASE_ANON_KEY=public-placeholder npm run build:ait
npm run verify:release
```

위 `AIT_APP_NAME=nyam-mvp`, `AIT_ICON_URL=https://example.invalid/icon.png`, `VITE_NEIS_PROXY_URL=https://example.invalid/functions/v1/neis-proxy`, `VITE_SUPABASE_ANON_KEY=public-placeholder`는 재현 가능한 로컬 패키징 증거만을 위한 비밀이 아닌 placeholder이며 QR/운영 빌드 값이 아닙니다. 운영 빌드에는 앞 절의 실제 설정을 process 환경 또는 커밋되지 않은 `.env`로 제공합니다. 산출물 byte 크기는 환경 값, dependency, 빌드 도구 버전에 따라 달라질 수 있으므로 고정 불변값으로 판정하지 않고, 각 실행의 verifier 출력과 100 MiB 미만 여부를 보관합니다.

`verify:web`는 빠른 웹 preflight입니다. `verify:release`는 최종 `.ait`가 없으면 실패하며, 설치된 공식 AIT reader로 magic과 인덱스를 확인하고 모든 항목을 실제로 읽습니다. 압축 해제 합계 100 MiB 이상, 중복·경로 탈출·symlink 유사 항목, 미허용 형식, 깨진 HTML 자산, ZIP local/central header 불일치·data descriptor·ZIP64·malformed extra/comment, 모든 AIT metadata/entry 이름/comment와 웹/RN bundle·map·JSON·HTML·CSS 및 허용된 산출물의 금지 표식, 빈/누락/추가되거나 IHDR 의미가 잘못된 레벨 PNG를 실패시킵니다. 소스맵과 문서는 검사에서 제외하지 않으며 오류는 발견한 값이나 환경 변수를 출력하지 않습니다.

웹 빌드는 `index.html`을 직접 진입점으로 사용하며 내부 화면 전환은 WebView의 클라이언트 라우터가 처리합니다. 앱인토스 배포 외의 정적 호스트나 `/today` 같은 딥링크를 지원하려면 호스트의 SPA fallback을 별도로 검증합니다. 이 MVP는 앱인토스가 번들을 제공하는 흐름 외의 호스팅을 전제로 하지 않습니다.

## 검수 증거 체크리스트

- [ ] 개인정보 처리방침과 지원 안내의 토스 미니앱 섹션에서 기기 저장, 삭제 가능성, NEIS 중계 범위, 기존 iOS/Android 설명 분리를 확인한다. 기존 정책 URL과 GitHub Issues 문의 채널을 바꾸지 않는다.
- [ ] 콘솔 sandbox/QR에서 학교 설정 → 실제 급식 → 세 가지 기록 → XP/레벨 → 앱 재실행 후 로컬 보존 → **내 데이터 삭제**를 캡처한다. 실제 값·키·개인 식별 정보·학교 상세 주소는 가린다.
- [ ] 실제 토스 QR 테스트에서 학교 검색, 급식, `RATE_LIMITED`/서비스 제한 상태, CORS를 확인한다. QR 테스트 origin과 운영 origin은 각각 별도로 점검한다.
- [ ] 지원되는 iOS와 Android 기기에서 같은 핵심 흐름, 글자/터치, 오류 상태, 네트워크 재시도를 기록한다. 네이티브 앱 설치나 외부 사이트를 핵심 기능의 대체 증거로 쓰지 않는다.
- [ ] Task 11에서 실제 Supabase 프로젝트 지역·호출/로그 보관 설정·Supabase/NEIS 제공자 정책을 확인하고 정책 문구와 검수 자료를 갱신한다. 이 저장소는 아직 QR·실기기·승인 증거를 주장하지 않는다.
- [ ] `npm run build:web`, `npm run verify:web`, `npm run build:ait`, `npm run verify:release`, 테스트/타입 검사와 최종 `.ait` verifier 출력을 보관한다. 승인 전에도 토스의 최신 비게임 출시 체크리스트를 대조한다. [앱인토스 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html)
