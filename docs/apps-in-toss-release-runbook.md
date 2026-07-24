# 냠냠레벨업 앱인토스 무료 운영·검수 런북

이 문서는 토스 미니앱 MVP만 다룹니다. 기존 iOS/Android 앱의 사진, 부모 연결, 서버 동기화 고지는 그대로 유지하며, 이를 미니앱에 배포하거나 사용하지 않습니다. 미니앱은 토스 `Storage`의 기기 로컬 데이터와 NEIS 요청을 중계하는 `neis-proxy` Edge Function 하나만 사용합니다. 앱인토스 검수 또는 출시는 토스의 판단이며 이 체크리스트가 승인을 보장하지는 않습니다.

## 운영 경계와 공개 정보

- 기기에만 저장: 별명, 선택 학교, 알레르기, 식사 기록, XP, 레벨, 급식 캐시. 토스 앱/미니앱 삭제, 토스 저장소 삭제, 기기 변경 시 사라질 수 있으며 설정의 **내 데이터 삭제**로 지웁니다.
- 중계로 전달: 학교 검색어 또는 선택 학교 코드와 날짜뿐입니다. `neis-proxy`는 사용자 기록을 저장하지 않습니다.
- Supabase 역할: Edge Function 실행과 그 비밀 설정뿐입니다. **Supabase DB, Auth 사용자, Storage, Realtime은 생성·사용·연결하지 않습니다.**
- 공개 가능한 키: Supabase Dashboard **Settings → API Keys**의 공개 anon/publishable 키만 `VITE_SUPABASE_ANON_KEY`로 클라이언트 빌드에 넣습니다. Supabase는 publishable/legacy anon 키를 브라우저용으로 설명하고, secret/service-role 키는 브라우저에 두면 안 된다고 명시합니다. [Supabase secrets guide](https://supabase.com/docs/guides/functions/secrets)
- 금지: service-role/secret key, NEIS API 키, 콘솔에서 발급한 실제 값, 유료 토스 기능, 자동 결제, 자동 요금제 업그레이드. 키·값·전체 origin 문자열이 보이는 화면을 검수 캡처나 이슈에 올리지 않습니다.

## 한 번만 준비할 설정

1. 로컬 전용 `apps-in-toss/.env`에 `AIT_APP_NAME`, `AIT_ICON_URL`, `VITE_NEIS_PROXY_URL`, `VITE_SUPABASE_ANON_KEY`의 실제 값을 넣습니다. 값은 각 콘솔의 해당 필드에서 복사하고, `.env`를 커밋하지 않습니다.
2. `VITE_NEIS_PROXY_URL`은 Supabase Dashboard **Edge Functions → neis-proxy**에서 확인한 함수 URL입니다. URL 형식과 함수 배포 절차는 [Supabase Edge Function 배포 문서](https://supabase.com/docs/guides/functions/deploy)를 따릅니다.
3. Supabase Dashboard **Edge Functions → Secrets**에 `NEIS_API_KEY`와 `NEIS_ALLOWED_ORIGINS`만 등록합니다. `NEIS_API_KEY`에는 NEIS 제공자 콘솔에서 발급·승인된 키를 직접 복사합니다. 클라이언트 `.env`, Git, 로그, QR 캡처에 넣지 않습니다. Secrets 변경은 재배포 없이 함수에서 사용할 수 있습니다. [Supabase secrets guide](https://supabase.com/docs/guides/functions/secrets)
4. `NEIS_ALLOWED_ORIGINS`에는 아래처럼 프로토콜·호스트만 쉼표로 연결하여 **정확히** 넣습니다. 끝 `/`, 와일드카드, 부분 도메인, 공백으로 된 별도 항목을 넣지 않습니다. `<appName>`은 `AIT_APP_NAME`의 실제 앱 이름으로 치환합니다.

   ```text
   https://<appName>.apps.tossmini.com,https://<appName>.private-apps.tossmini.com
   ```

   - 운영 origin: `https://<appName>.apps.tossmini.com`
   - 콘솔 QR 테스트(sandbox) origin: `https://<appName>.private-apps.tossmini.com`
   - 로컬 브라우저로 프런트엔드까지 확인할 때만 `http://localhost:5173`을 별도 항목으로 임시 추가하고, 출시 전 제거합니다.

   토스는 QR 테스트와 실제 서비스 환경의 CORS/네트워크 동작이 다를 수 있다고 안내하며, 위 두 origin을 각각 허용하도록 명시합니다. [앱인토스 미니앱 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html)

5. 함수 코드는 `supabase/functions/neis-proxy/`만 배포합니다. 이 함수는 요청을 `searchSchools`와 `fetchMeals`로 제한하고 사용자 레코드를 쓰지 않습니다. 배포 전에는 부모 동기화 함수, migrations, DB 테이블, Auth 사용자, Storage bucket, Realtime 채널을 이 미니앱 구성에 추가하지 않았는지 다시 확인합니다.

## 키 회전과 중단

### NEIS 키 회전

1. NEIS 제공자 콘솔에서 새 키를 발급하고 기존 키는 아직 철회하지 않습니다.
2. Supabase **Edge Functions → Secrets**에서 `NEIS_API_KEY`만 새 값으로 교체합니다. 값은 화면이나 명령 출력에 붙여 넣지 않습니다.
3. 허용된 QR origin에서 학교 검색과 급식 조회를 각각 한 번 실행하고, 함수 로그에서 상태와 오류 코드만 확인합니다. 키나 요청 본문을 기록하지 않습니다.
4. 성공을 확인한 뒤에만 NEIS 제공자 콘솔에서 기존 키를 철회합니다. 실패하면 새 키를 노출하지 말고 비밀 설정을 이전 상태로 되돌린 뒤 원인을 조사합니다.

### 무료 한도 접근 또는 이상 요청 시

1. 앱은 `RATE_LIMITED` 또는 서비스 제한 메시지를 표시하고 자동 결제·자동 업그레이드를 하지 않습니다. 실제 학교 조회는 샘플 급식으로 자동 대체하지 않습니다.
2. 즉시 NEIS 호출을 막아야 하면 `NEIS_ALLOWED_ORIGINS`를 빈 값으로 바꿉니다. 현재 함수는 허용 origin이 비어 있으면 NEIS를 호출하지 않고 `NOT_CONFIGURED`/503을 반환합니다. 이는 재배포 없이 적용되는 안전한 임시 중단입니다.
3. 계속 중단할 때는 프로젝트를 확인한 뒤 `neis-proxy`만 삭제/undeploy합니다. CLI의 `supabase functions delete neis-proxy --project-ref <project-ref>`는 원격 함수만 삭제하고 로컬 소스는 지우지 않습니다. 프로젝트 전체를 삭제하거나 데이터 제품을 새로 켜지 않습니다. [Supabase CLI Functions reference](https://supabase.com/docs/reference/cli/supabase-orgs-list)
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
npm run verify:release
npm run build:ait
```

`verify:release`는 `dist/` 누락, 압축 해제 크기 100 MiB 이상, 직접 진입점/자산 참조 오류, 금지 표식, 빈/누락/추가된 레벨 PNG를 실패시킵니다. 소스맵과 문서는 내용 표식 검사에서 제외하되 bundle 크기에는 포함합니다. verifier 오류는 발견한 비밀 값이나 환경 변수 내용을 출력하지 않습니다.

웹 빌드는 `index.html`을 직접 진입점으로 사용하며 내부 화면 전환은 WebView의 클라이언트 라우터가 처리합니다. 앱인토스 배포 외의 정적 호스트나 `/today` 같은 딥링크를 지원하려면 호스트의 SPA fallback을 별도로 검증합니다. 이 MVP는 앱인토스가 번들을 제공하는 흐름 외의 호스팅을 전제로 하지 않습니다.

## 검수 증거 체크리스트

- [ ] 개인정보 처리방침과 지원 안내의 토스 미니앱 섹션에서 기기 저장, 삭제 가능성, NEIS 중계 범위, 기존 iOS/Android 설명 분리를 확인한다. 기존 정책 URL과 GitHub Issues 문의 채널을 바꾸지 않는다.
- [ ] 콘솔 sandbox/QR에서 학교 설정 → 실제 급식 → 세 가지 기록 → XP/레벨 → 앱 재실행 후 로컬 보존 → **내 데이터 삭제**를 캡처한다. 실제 값·키·개인 식별 정보·학교 상세 주소는 가린다.
- [ ] 실제 토스 QR 테스트에서 학교 검색, 급식, `RATE_LIMITED`/서비스 제한 상태, CORS를 확인한다. QR 테스트 origin과 운영 origin은 각각 별도로 점검한다.
- [ ] 지원되는 iOS와 Android 기기에서 같은 핵심 흐름, 글자/터치, 오류 상태, 네트워크 재시도를 기록한다. 네이티브 앱 설치나 외부 사이트를 핵심 기능의 대체 증거로 쓰지 않는다.
- [ ] `npm run build:web`, `npm run verify:release`, `.ait` 빌드 결과, 테스트/타입 검사 출력을 보관한다. 승인 전에도 토스의 최신 비게임 출시 체크리스트를 대조한다. [앱인토스 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html)
