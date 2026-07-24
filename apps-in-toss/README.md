# 냠냠레벨업 앱인토스 클라이언트

토스 안에서 동작하는 무료 MVP입니다. 별명, 학교, 알레르기, 식사 기록, XP, 레벨, 급식 캐시는 토스 `Storage`에 저장합니다. 서버는 NEIS 요청을 중계하는 Supabase Edge Function `neis-proxy` 하나뿐이며, 미니앱 코드는 이 데이터를 Supabase DB/Auth/Storage/Realtime에 사용자 기록으로 작성하지 않습니다. 학교 검색어 또는 학교 코드·날짜와 통상적인 요청/호출 메타데이터는 Edge 및 NEIS 처리 과정에 전달될 수 있습니다.

기존 iOS/Android 앱의 사진·부모 연결 기능은 이 미니앱의 기능이나 데이터 흐름이 아닙니다. 이 디렉터리는 네이티브 앱을 변경하거나 대체하지 않습니다.

## 설정

로컬 전용 `.env`를 만들고 다음 **이름만** 설정합니다. `.env`와 실제 값은 커밋하거나 검수 자료에 넣지 않습니다.

```text
AIT_APP_NAME
AIT_ICON_URL
VITE_NEIS_PROXY_URL
VITE_SUPABASE_ANON_KEY
```

- `AIT_APP_NAME`, `AIT_ICON_URL`: 앱인토스 콘솔에서 관리하는 앱 이름과 아이콘 URL을 복사해 사용합니다.
- `VITE_NEIS_PROXY_URL`: 배포된 `neis-proxy` Edge Function URL입니다.
- `VITE_SUPABASE_ANON_KEY`: 현재 클라이언트는 같은 값을 `apikey`와 `Authorization: Bearer`로 전송하고, `neis-proxy`는 기본 `verify_jwt`를 켠 채 배포합니다. 따라서 Dashboard API Keys의 **기존 JWT 형태 `anon` 키**를 사용해야 합니다. 새 `sb_publishable_` 키는 JWT가 아니므로 현재 Bearer 설계에서 허용되지 않습니다. [Supabase Authorization headers](https://supabase.com/docs/guides/functions/auth-headers)
- `NEIS_API_KEY`, `NEIS_ALLOWED_ORIGINS`: 클라이언트 `.env`가 아니라 Supabase Edge Function Secrets에만 둡니다. `service_role` 및 `sb_secret_`를 포함한 secret key와 NEIS 키는 어떤 경우에도 미니앱, 번들, 스크린샷, 문서에 넣지 않습니다. `verify_jwt`를 끄거나 `--no-verify-jwt`로 배포하지 않습니다.

## 명령

```bash
npm test
npm run typecheck
npm run build:web
npm run verify:web
npm run build:ait
npm run verify:release
```

`verify:web`는 웹 산출물을 빠르게 검사합니다. `verify:release`는 업로드할 최종 `.ait`가 없으면 실패하며, 공식 AIT reader로 모든 인덱스 항목을 읽어 실제 압축 해제 크기, magic, 중복·경로 탈출·symlink 유사 항목, 웹/RN bundle·map·JSON·HTML·CSS와 기타 안전 허용 항목의 금지 표식, HTML 자산, PNG 서명을 검사합니다. 소스맵과 문서도 검사에서 제외하지 않으며 오류는 발견한 값이나 환경 변수를 출력하지 않습니다.

웹 클라이언트는 브라우저 라우팅을 사용합니다. 앱인토스가 번들의 루트 진입점(`index.html`)을 열고 그 뒤의 화면 전환을 WebView 안에서 처리한다는 전제입니다. 외부 정적 호스트로 따로 배포하거나 `/today` 같은 경로를 직접 열어야 한다면, 해당 호스트의 SPA fallback을 먼저 검증해야 합니다.

## 무료 운영 경계

- 금지: Supabase Database, Auth 사용자, Storage, Realtime과 유료 토스 기능. `parent-sync`와 네이티브 앱용 데이터 흐름을 이 미니앱 배포에 연결하지 않습니다.
- 무료 한도·NEIS 요청 제한이 발생하면 `RATE_LIMITED` 또는 서비스 제한 UI를 보여 주고 나중에 다시 시도하게 합니다. 자동 요금제 변경, 자동 결제, 유료 기능 활성화는 하지 않습니다.
- 운영 절차, CORS origin, 키 회전, 사용량 감시, 중단 방법, 검수 증거는 [출시 런북](../docs/apps-in-toss-release-runbook.md)을 따릅니다.

앱인토스 검수·출시는 토스의 별도 판단 대상이며, 이 저장소의 검사 통과가 승인을 보장하지는 않습니다.
