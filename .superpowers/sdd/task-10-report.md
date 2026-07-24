# Task 10 report — Toss policy and release guardrails

## Scope and SHA

- Base SHA: `43131ad54a1932878b5e35950794e08ccf775cb4`
- Initial Task 10 SHA: `29b141a0431d22b9f7796868ccb97cf6bf1451cd`
- Scope: Apps-in-Toss disclosure, final upload-artifact gate, zero-cost/review runbook, shared-contract packaging repair, and adversarial verifier fixtures.
- Preserved: existing privacy/support URLs, published GitHub Issues support contact, and separately labelled iOS/Android photos and parent-sync disclosures.
- The privacy policy's effective/revision date `2026-07-24` is intentional: it is the workspace's specified Asia/Seoul system date for this task, not an inferred Git timestamp. Reviewer: please accept this system date even if a commit timestamp differs.

## Delivered

- Privacy and support now distinguish local Toss Storage from Edge/NEIS processing. They disclose relay body fields (school search text or school codes/date), standard Origin/IP/User-Agent/header and invocation/log metadata, processing purpose, and that mini-app code does not write user records to Supabase DB/Auth/Storage/Realtime. They do not claim an unverified provider retention period or processing region; Task 11 must verify the selected project and provider policies before submission. The policy revision date is `2026-07-24`.
- README and runbook require the current client’s legacy JWT-shaped `anon` key because it sends the key as `Authorization: Bearer` while default `verify_jwt` remains enabled. They explicitly reject `sb_publishable_`, service-role, and `sb_secret_` for this design.
- The runbook uses the exact production/QR origins, documents NEIS rotation and `supabase secrets unset NEIS_ALLOWED_ORIGINS --project-ref <project-ref>` as the supported safe-disable action, specifies a 503/`NOT_CONFIGURED` confirmation, then targeted `neis-proxy` deletion only if needed. It retains the zero-cost/no-auto-upgrade and `RATE_LIMITED` guidance.
- `verify:web` is a preflight only. `verify:release` now requires a final `.ait`, parses its ZIP central directory independently of the protobuf index, rejects ZIP64/multidisk/malformed/duplicate/hidden/traversal/Windows-drive/symlink-like entries, and requires an exact ZIP↔index match. It reads and checks every actual entry against index uncompressed size and SHA-256, scans metadata/app/package data and all artifacts including maps/docs/UTF-16/JWT role claims, validates HTML assets, and validates seven structurally complete growth PNGs. Failure messages do not echo values.
- Release fixtures cover missing final artifact; valid AIT writer round-trip; docs and map markers; `sb_secret_`; UTF-16 at both byte alignments; non-anon JWT role; traversal, duplicate, and Windows-drive entries; hidden ZIP entry; central size/digest mismatch; metadata secret; unsupported artifacts; unquoted missing HTML assets; a parent path containing `docs`; root symlink; extra level asset; and corrupt/truncated PNGs.
- Added a real `0.1.0` version plus `./package.json` export to `@nyam/neis-contract` and refreshed the client lockfile. This repairs the Apps-in-Toss dependency collector without changing shared imports or vendoring a duplicate package.

## Verification evidence

Executed from `apps-in-toss/` with process-only non-secret placeholders for AIT build:

```text
npm run test:release  # 15 passed
npm test              # 14 files, 115 tests passed
npm run typecheck     # passed
npm run build:web     # passed
npm run verify:web    # 10,051,083 bytes across 10 files
npm run build:ait     # passed; real .ait generated
npm run verify:release
# Final AIT release checks passed: 31,972,319 bytes across 18 entries
```

Also passed:

```text
rg -n "토스 미니앱|내 데이터 삭제|NEIS|Supabase|처리" \
  marketing-site/dist/privacy.html marketing-site/dist/support.html
git diff --check
```

`deno` was not installed in this environment, so shared/Deno tests were not run. The Vite build emitted a non-blocking chunk-size advisory. The temporary `.ait` and generated `.granite/app.json` were removed after verification and are not committed. This report does not claim QR, physical iOS/Android, review, or approval evidence; those remain Task 11 work.

## Official operational sources

- [앱인토스 미니앱 출시 안내](https://developers-apps-in-toss.toss.im/development/deploy.html) — production and QR-test CORS origins, deployment/review flow.
- [Supabase Authorization headers](https://supabase.com/docs/guides/functions/auth-headers) — default `verify_jwt` and bearer/API-key behavior.
- [Supabase API-key compatibility](https://supabase.com/docs/guides/getting-started/api-keys) — legacy JWT anon versus new publishable/secret key limitation for Edge Functions.
- [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets) — Dashboard secrets.
- [Supabase Edge Function deployment](https://supabase.com/docs/guides/functions/deploy) — function URL and deployment flow.
- [Supabase secrets unset CLI](https://supabase.com/docs/reference/cli/supabase-secrets-unset) and [functions delete CLI](https://supabase.com/docs/reference/cli/supabase-functions-delete) — targeted emergency operations.
- [Supabase Function invocation usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations) and [pricing](https://supabase.com/pricing) — monitoring and current plan terms.
