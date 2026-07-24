# Task 10 report — Toss policy and release guardrails

## Scope and SHA

- Base SHA: `43131ad54a1932878b5e35950794e08ccf775cb4`
- Scope: Apps-in-Toss local-only disclosure, release verifier, zero-cost/review runbook, and verifier fixtures.
- Preserved: existing privacy/support URLs, the published GitHub Issues support contact, and the separately labelled iOS/Android photos and parent-sync disclosures.

## Delivered

- Added clearly labelled Toss mini-app disclosure to privacy and support pages: device-only Toss Storage, deletion/device-change loss, in-app **내 데이터 삭제**, NEIS relay request scope, and Edge-Function-only Supabase use.
- Kept the existing iOS/Android device, photo, parent connection, and native deletion descriptions separate so the mini-app does not misrepresent the native apps.
- Added importable `verifyRelease()` and `npm run verify:release`. It refuses a missing/non-directory `dist`, symbolic links, bundles at or above 100 MiB uncompressed, broken direct entry assets, unsafe artifact markers without echoing a match, and anything other than exactly seven non-empty level PNGs.
- Added temporary-fixture Node tests for missing bundle, valid bundle with map/docs exclusions, unsafe marker in an unknown artifact, and an extra level image. The regular Vitest configuration excludes the Node-only fixture suite.
- Added client README and release runbook covering public anon key versus forbidden service-role key, exact production/QR CORS origins, NEIS rotation, safe disable/undeploy, usage monitoring, zero-cost/no-auto-upgrade policy, `RATE_LIMITED` behavior, and sandbox/QR/iOS/Android review evidence.

## Verification evidence

Executed from `apps-in-toss/`:

```text
npm run test:release  # 4 passed
npm test              # 14 files, 115 tests passed
npm run typecheck     # passed
npm run build:web     # passed
npm run verify:release
# Release checks passed: 10051083 bytes across 10 files
```

Also passed:

```text
rg -n "토스 미니앱|기기에만 저장|내 데이터 삭제|NEIS" \
  marketing-site/dist/privacy.html marketing-site/dist/support.html
git diff --check
```

The Vite build emitted its existing chunk-size advisory; it did not fail the build, and the uncompressed release bundle is below the required 100 MiB limit.

## Official operational sources

- [앱인토스 미니앱 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html) — production and QR-test CORS origins, deployment/review flow.
- [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets) — Dashboard secrets and browser-safe public versus forbidden secret keys.
- [Supabase Edge Function deployment](https://supabase.com/docs/guides/functions/deploy) — function URL and deployment flow.
- [Supabase Function invocation usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations) — usage monitoring.
- [Supabase CLI Functions reference](https://supabase.com/docs/reference/cli/supabase-orgs-list) — targeted function deletion.
- [Supabase pricing](https://supabase.com/pricing) — live plan terms; no unstable quota number is hardcoded.
