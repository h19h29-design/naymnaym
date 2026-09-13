# Daily AI Meal Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 오늘 식단을 하루 한 번 AI가 해설하고 iOS·Android 기기에 저장해 재열람한다.
**Architecture:** 독립된 v2 일일 평가 API와 최소 사용 장부. 네이티브 Core Data/Room 기록 저장소와 기존 급식 상세/오늘 진입점을 연결한다. 서버와 모바일은 아래 고정 JSON 계약을 공유한다.
**Tech Stack:** Node 24 built-ins, SwiftUI/Core Data, Kotlin Compose/Room.
**Spec:** `docs/superpowers/specs/2026-09-13-daily-ai-meal-review-design.md`

**Execution status (2026-09-13):** Implementation tasks1–3 complete and reviewed; local-development integration complete. Final evidence and per-item outcomes are in `.superpowers/sdd/2026-09-13-daily-ai-meal-review/progress.md` and task reports. iOS615 XCTest, Android20 dedicated unit/6 instrumented plus required build/lint, Node32 pass. Actual v2 live verification is iOS-only; Android synthetic transport/UI passed but local-HTTP/live-v2 E2E remains an explicitly disclosed release verification gap. Public operation remains HOLD; no commit/push/deploy.

## Global Constraints

- 범위: iOS·Android, 오늘 식단 전체 평가, 하루 1회 성공 생성, 기기 내 기록, 과거 평가 열람.
- 제외: 자유 채팅, 실제 영양사 상담, 클라우드 기록 동기화, 토스, 스토어 제출, 운영 서버 배포, 제공자 변경.
- 기존 사용자 데이터·비밀 파일 보존. Go 키/클라이언트 토큰 출력, 문서화, Git 저장 금지. 이번 작업은 커밋/푸시하지 않는다.
- 서버 Asia/Seoul 날짜, 인증된 개발 자격 증명당 하루 성공 1회/최대 제공자 시도 3회. 운영 사용자별 인증은 공개 출시 전 별도 작업.
- 실제 영양사로 표시하지 않는다. `AI 영양 안내`, 성공 `AI가 생성한 영양 안내`, 실패 `기본 영양 안내`.
- 공급자에 학교·메뉴 이름·식단 날짜·실제 섭취 기록·등록 알레르기를 보내지 않는다. 모든 메뉴의 개인 알레르기 판단은 로컬이다.
- 동의 전, 과거/미래, 급식 없음, 모든 후보가 불명확/알레르기 주의인 경우 AI 미호출.
- AI 기록만 확인 후 삭제. 로컬 삭제로 서버 한도가 초기화되지 않는다.

## Shared wire contract

POST `/v2/meal-coach/daily`, same Bearer development credential as v1. Development clients derive path from existing whitelisted localhost base; RELEASE stays disconnected.

```json
{"requestId":"00000000-0000-4000-8000-000000000001","sessionId":"00000000-0000-4000-8000-000000000002","items":[{"id":"m0","nutrients":["carbohydrate"]}],"wholeMeal":{"protein":23}}
```

Exact keys; UUID IDs. Items 1..30, id `m0`..`m29` stable original menu index, unique. Nutrient IDs only fiber/vitamin/protein/iron/calcium/carbohydrate, unique at most 6, each candidate must have at least 1. Apps omit allergy-intersecting and unknown candidates. `wholeMeal` keys protein/carbs/fat only, finite >0 <=1000; use real source values only. Provider receives only items/wholeMeal and session header; never requestId or server day/subject.

```json
{"source":"ai","reviewId":"00000000-0000-4000-8000-000000000001","day":"2026-09-13","generatedAt":"2026-09-13T04:00:00.000Z","model":"deepseek-v4.1-flash","policyVersion":"daily-v1","summary":"오늘 영양 구성을 살펴봤어.","benefit":"에너지원이 되는 영양소를 만날 수 있어.","highlights":[{"itemId":"m0","nutrient":"carbohydrate","reason":"활동에 쓰이는 에너지원이야."}],"caution":"실제로 먹은 양은 알 수 없어.","tip":"다음 식사에서도 다양한 음식을 만나 보자."}
```

Provider returns only summary/benefit/highlights/caution/tip. Text fields 1..240 Korean chars; highlight max2 unique requested IDs, nutrient must belong to chosen item. Same existing numeric/medical/food-safety/URL guards. Apps show local menu label plus fixed canonical nutrient-role text for highlight, not unchecked provider reason; preserve reason in validated record for audit. 16KB response, 8KB request, 15s timeout, max_tokens1100, JSON mode, no automatic retry.

Errors `{error:code,reason?:code}`: 401 unauthorized; 400 invalid_request; 409 request_conflict/daily_used/in_progress/recovery_unavailable; 429 daily_attempt_limit/usage_limit; 502 answer_unavailable; 503 storage_unavailable/not_configured. `recovery_unavailable` means a persisted pending attempt outlived its lease after a process interruption; every request for that subject/day remains fail-closed so an uncertain provider success cannot cause another paid generation. Identical request after success can replay in-memory answer for <=90 seconds; then daily_used. Different payload with same request ID is request_conflict. Client retains pending request ID for manual retry only; transient connectivity recovery cannot create another generation for the same successful request.

## Task 1: Server daily contract and durable quota

**Files:** create `server/meal-coach/daily.mjs`, `daily.test.mjs`, `daily-ledger.mjs`; modify `coach.mjs` only to export reusable safe validation/transport helpers if needed; modify `serve.mjs` to mount both handlers with explicit shared request budget.
**Interfaces:** `createDailyCoachHandler(config,{ledger,fetcher,now,budget}) -> async Request=>Response`; `DailyLedger(path)` owns SQLite minimal state; shared `budget` has `take():boolean` and `release():void` so only an acquired provider-call slot consumes the process allowance. `now` defaults Date.now. No provider content persisted.

- [ ] RED: tests exercise real temp ledger with fake upstream, reject duplicate success/restart and third failed attempt limit; wrong token/personal fields cause zero upstream calls.
```js
assert.equal((await handler(request())).status,200);
assert.equal((await handler(differentRequest())).status,409);
assert.equal(calls,1);
```
- [ ] Run `node --test server/meal-coach/daily.test.mjs` and capture expected RED.
- [ ] Implement strict DTO/output validation, server day from clock, atomic claim/complete state, 90s memory replay, max3 attempts, global budget, 15s deadline. Use parameterized SQLite statements and private DB permissions. Failed writes fail closed before upstream call.
```js
const day=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(now()));
```
- [ ] Tests for expiry, midnight, reused ID/different payload, concurrent calls, network failure, crash pending state, secret echo, invalid menu/nutrient, request/output size, no raw error, and quota-only disk contents. Run all Node tests.

## Task 2: iOS daily records and native UI

**Files:** create `NaymNaymLevelUp/Rebuild/Meal/DailyMealReview.swift`, `DailyMealReviewStore.swift`, `NaymNaymLevelUp/Rebuild/Child/DailyMealReviewView.swift`; modify `RebuildManagedModel.swift`, appropriate managed object file, `RebuildPersistentStore.swift` for additive migration, `MealDayDetailView.swift`, `TodayForestView.swift`, `SettingsView.swift` as actual active settings entry. Add `NaymNaymLevelUpTests/DailyMealReviewTests.swift`, persistence migration test; register files in project if required.
**Interfaces:** `DailyMealReviewRecord: Codable` includes local context key/day/meal snapshot/result; `DailyMealReviewStore.load(context:day:)`, `save(record:)`, `deleteAll()`; UI consumes RebuildMealDay, current profile/school context and allergies, managedObjectContext. Same endpoint/DTO above.

- [ ] RED: real in-memory Core Data store persists/reloads one dated record; current allergies suppress a stored highlight; factory excludes flagged/unknown items and never includes menu names.
```swift
XCTAssertEqual(try store.load(context: "fixture", day: "2026-09-13")?.response.source, "ai")
XCTAssertTrue(factoryRequest.items.allSatisfy { $0.id != "m1" })
```
- [ ] Test against missing implementation, then implement Codable validated DTO, safe candidate mapping, immutable snapshot keyed local profile/school/date/lunch, pending id lifecycle, Korea-day eligibility. Existing meal model represents lunch; label it as lunch without inventing other meal types.
- [ ] Add persistent record entity with additive migration retaining legacy source model in memory for migration tests. Do not destroy existing store on migration error. Persist before marking UI saved; report local save failure and permit same-result save retry without upstream call.
- [ ] Connect one entry in today character area and daily/weekly/monthly detail to new view. Reuse animation components. Saved result wins over current-day eligibility, compare meal snapshot for changed-menu note, current allergy mask always applied.
- [ ] Confirmed settings action removes only review entity rows; no XP/meal mutation. Test restart, school separation, corrupted record, delete scope, past/future/no meal/no consent, failure fallback.
- [ ] Build/test iOS suite via XcodeBuildMCP or xcodebuild at existing `/tmp/nyam-companion-derived`, simulator `8ECAF063-8D75-4944-B20C-A2B0ED51271B`. Capture QA evidence; no real provider requests without parent coordination.

## Task 3: Android daily records and native UI

**Files:** create `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/DailyMealReviewDomain.kt`, `DailyMealReviewClient.kt`, `DailyMealReviewScreen.kt`, `DailyMealReviewStore.kt`; modify `rebuild/data/RebuildEntities.kt`, `RebuildDaos.kt`, `RebuildDatabase.kt`, `child/TodayForestScreen.kt`, `MealScheduleScreen.kt`, `RebuildSettingsScreen.kt`, `ChildNavigation.kt` as needed. New unit tests `DailyMealReviewTest.kt` and instrumented `DailyMealReviewScreenTest.kt`, `DailyMealReviewMigrationTest.kt`; generated Room schema version2.
**Interfaces:** UI uses existing MealDay plus local profile/school key/current allergies; same shared v2 wire contract. `DailyMealReviewStore` load/save/deleteAll uses Room DAO and JSON Codable-equivalent data via existing kotlinx serialization. No new framework.

- [ ] RED: tests prove allergy/unknown candidate exclusion, source-label selection, response validator rejects unrequested highlight, saved result prevents a second client call.
```kotlin
assertEquals(1, clientCalls)
assertEquals("ai", store.load("fixture", "2026-09-13")?.response?.source)
```
- [ ] Run targeted test RED, implement strict DTO/serialization, timeout/no redirect/size cap mirroring existing client, DEBUG-only endpoint conversion to v2. Keep old APIs compiling but replace active coach entry.
- [ ] Add Room table/entity/DAO and explicit MIGRATION_1_2 CREATE TABLE (never destructive fallback). Preserve existing entities. Handle save failure without showing saved success, retain result for local save retry. Review-history deletion requires dialog and only clears its table.
- [ ] State machine: today Korea day + candidates + consent required; successful per-day record reused on re-entry/restart; 90s manual network recovery retains same requestId; use server errors to distinguish daily_used/attempt_limit/storage/error. Current allergies mask stored highlight; changed meal shows snapshot notice. No consumption/XP side effects.
- [ ] Integrate today character-area action and meal schedule detail for daily/weekly/monthly, plus active settings deletion. Use same four report sections and `AI 영양 안내` labels as spec, known source figures separate.
- [ ] Unit: past/future/no data, local scope separation, reload/deletion, invalid JSON, fallback vs AI. Instrumented: real Room v1→v2 preserves representative existing profile/meal/progress, basic and 1.5× font UI plus saved-record reopen.
- [ ] Run `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug -I ../scripts/android-test-classpath.gradle --no-daemon --console=plain '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g' --max-workers=2` from android. Start targeted tests first; full run after implementation. No real Go call in tests unless parent explicitly coordinates.
- [ ] Self-review and write report with exact RED/GREEN commands/results and changed paths. No commit/push/deploy, no subagents, no secret files or logs/hprof inspection.

## Task 4: Integration and release-readiness report

**Files:** update `server/meal-coach/README.md`, `design-qa.md`, this plan/ledger. No deployment configuration activation.
- [ ] Read task diffs against the contract, review each platform and server; resolve findings before completion.
- [ ] Run required native suites/builds and Node suite for integrated code. Compare stored AI labels, basic fallback, reopening, deletion confirmation and original XP data preservation.
- [ ] Use bounded synthetic live calls only after mocks pass; do not reset daily ledgers to bypass quotas. Different test principals use synthetic config only in offline tests. If daily live quota prevents second client verification, verify second client against a synthetic local HTTP service and report live limitation.
- [ ] Report exact verified scope, remaining operational authentication/Go usage/child safety gates; do not claim public deployment readiness from simulator success.

## Execution decisions

- Reuse existing isolated `codex/ios-growth-meal-polish-v2` worktree; preserve pre-existing dirty work.
- Root owns server and cross-platform contract; one native implementation worker may own Android while root works on nonoverlapping files. Never two implementation subagents at once. Fresh task review follows. User's explicit no-extra-approval preference selects execution in current session.
- Do not create commits solely to satisfy workflow templates; approved scope explicitly excludes commits/push. Review packages include working-tree diffs and new files, not HEAD-only ranges.
