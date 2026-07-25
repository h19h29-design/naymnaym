# 냠냠레벨업 부모 리포트·연결·동기화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이의 로컬 기록을 잃지 않는 멱등 동기화와 보호자 연결을 만들고, 근거와 데이터 부족 상태가 명확한 부모용 `요약 · 기록 · 설정` 경험을 양 플랫폼에 제공한다.

**Architecture:** 기존 `parent-sync` 엔드포인트는 v1 동작을 유지하고 v2 액션을 추가한다. 새 클라이언트는 로컬 sync envelope을 순서대로 업로드하며 서버는 이벤트 ID와 revision으로 중복을 제거한다. 부모 리포트는 공통 fixture 기반 집계 규칙으로 생성한다.

**Tech Stack:** Supabase PostgreSQL, Deno Edge Functions, Swift async/await, Core Data, URLSession, Kotlin Coroutines/Flow, Room, HttpURLConnection

## Global Constraints

- 기존 v1 초대·스냅샷 액션은 전환 기간에 계속 동작해야 한다.
- 아이의 개인 로컬 기록은 서버·네트워크 실패로 삭제하거나 되돌리지 않는다.
- 부모에게 공유되지 않도록 선택된 기록은 업로드하지 않는다.
- 자유 입력 채팅, 공개 프로필, 위치, 경쟁 순위를 추가하지 않는다.
- 주간 데이터가 3일 미만이면 점수 대신 `확인할 기록이 조금 더 필요해요`를 표시한다.
- 의료 진단이나 치료를 암시하는 문구를 사용하지 않는다.
- 연결·외부 링크·내보내기·삭제는 부모 영역에서만 실행한다.

## Target File Map

### 서버

- `supabase/migrations/20260725_parent_sync_v2.sql`: 세션 토큰, 이벤트, cursor, 삭제 요청
- `supabase/functions/parent-sync/v2-contract.ts`: 요청·응답 파서
- `supabase/functions/parent-sync/v2-sync.ts`: 멱등 upsert·snapshot·delete
- `supabase/functions/parent-sync/v2-sync_test.ts`: 순수 함수와 인증 테스트
- `supabase/functions/parent-sync/index.ts`: v2 action routing

### 공통 계약

- `contracts/native-rebuild/v1/parent-sync-contract.json`
- `contracts/native-rebuild/v1/weekly-report-fixtures.json`

### iOS

- `NaymNaymLevelUp/Rebuild/Parent/ParentSyncClient.swift`
- `NaymNaymLevelUp/Rebuild/Parent/ParentSyncQueue.swift`
- `NaymNaymLevelUp/Rebuild/Parent/WeeklyReportBuilder.swift`
- `NaymNaymLevelUp/Rebuild/Parent/GuardianGate.swift`
- `NaymNaymLevelUp/Rebuild/Parent/ParentNavigationView.swift`
- `NaymNaymLevelUp/Rebuild/Parent/ParentSummaryView.swift`
- `NaymNaymLevelUp/Rebuild/Parent/ParentHistoryView.swift`
- `NaymNaymLevelUp/Rebuild/Parent/ParentSettingsView.swift`

### Android

- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSyncClient.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSyncQueue.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/WeeklyReportBuilder.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/GuardianGate.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentNavigation.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSummaryScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentHistoryScreen.kt`
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSettingsScreen.kt`

---

### Task 1: v2 서버 스키마와 인증 계약

**Files:**
- Create: `supabase/migrations/20260725_parent_sync_v2.sql`
- Create: `supabase/functions/parent-sync/v2-contract.ts`
- Create: `supabase/functions/parent-sync/v2-sync.ts`
- Create: `supabase/functions/parent-sync/v2-sync_test.ts`
- Modify: `supabase/functions/parent-sync/index.ts`
- Create: `contracts/native-rebuild/v1/parent-sync-contract.json`

**Interfaces:**
- Produces actions: `connectInviteV2`, `upsertEventsV2`, `fetchSnapshotV2`, `deleteParentDataV2`
- Produces: parent session token returned once; only SHA-256 hash stored
- Consumes: event `id`, `recordId`, `revision`, `kind`, `payload`, `deletedAt`

- [ ] **Step 1: Write failing v2 contract tests**

```typescript
Deno.test("parent session token is never returned from stored row", () => {
  const response = connectResponse({
    parent_session_token_hash: "server-only",
    child_link_id: "11111111-1111-1111-1111-111111111111",
  }, "plain-token-returned-once");
  assertEquals(response.parentSessionToken, "plain-token-returned-once");
  assertEquals(JSON.stringify(response).includes("hash"), false);
});

Deno.test("higher revision wins and duplicate event is idempotent", () => {
  const merged = mergeEvents(
    [{ id: "event-1", revision: 2 }],
    [{ id: "event-1", revision: 1 }]
  );
  assertEquals(merged, [{ id: "event-1", revision: 2 }]);
});
```

- [ ] **Step 2: Run the new Deno tests**

Run: `deno test supabase/functions/parent-sync/v2-sync_test.ts`

Expected: FAIL because v2 modules do not exist.

- [ ] **Step 3: Add tables, grants, indexes, and v2 routing**

Migration requirements:

```sql
create table public.nyam_parent_sessions_v2 (
  session_id uuid primary key default gen_random_uuid(),
  child_link_id uuid not null references public.nyam_parent_links(child_link_id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table public.nyam_parent_events_v2 (
  event_id uuid primary key,
  child_link_id uuid not null references public.nyam_parent_links(child_link_id) on delete cascade,
  record_id uuid not null,
  revision integer not null check (revision >= 1),
  kind text not null check (kind in ('meal','progress')),
  payload jsonb not null,
  deleted_at timestamptz,
  updated_at timestamptz not null default now()
);
```

Add a unique `(child_link_id, record_id, kind)` index, sync cursor table, deletion audit table containing no meal payload, and revoke direct `anon`/`authenticated` table access. Edge Function service-role access remains server-side.

`index.ts` must route v2 actions before the existing v1 switch and return the same CORS/error envelope shape without logging tokens or payloads.

- [ ] **Step 4: Run server tests and SQL inspection**

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Expected: `native-rebuild-contract-sync: PASS`.

Run: `deno test supabase/functions/parent-sync/*_test.ts`

Expected: PASS.

Run: `rg -n 'parentSessionToken|token_hash|console\\.log' supabase/functions/parent-sync`

Expected: no log statement containing tokens; response type exposes plain token only from `connectInviteV2`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260725_parent_sync_v2.sql supabase/functions/parent-sync contracts/native-rebuild/v1/parent-sync-contract.json NaymNaymLevelUp/Resources/RebuildContracts android/app/src/main/assets/rebuild-contracts
git commit -m "feat: add parent sync v2 contract"
```

### Task 2: 공통 주간 리포트 규칙

**Files:**
- Create: `contracts/native-rebuild/v1/weekly-report-fixtures.json`
- Create: `NaymNaymLevelUp/Rebuild/Parent/WeeklyReportBuilder.swift`
- Create: `NaymNaymLevelUpTests/WeeklyReportBuilderTests.swift`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/WeeklyReportBuilder.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent/WeeklyReportBuilderTest.kt`

**Interfaces:**
- Produces: `WeeklyReport(recordedDays, frequentMisses, positiveChanges, state)`
- Produces state: `insufficientData` when fewer than 3 distinct dates

- [ ] **Step 1: Add exact shared fixtures**

Include:

```json
{
  "name": "two days is insufficient",
  "records": [
    {"date":"2026-07-20","menu":"시금치나물","status":"difficultToday","nutrients":["fiber","vitamin"]},
    {"date":"2026-07-21","menu":"우유","status":"allergyAvoided","nutrients":["calcium"]}
  ],
  "expected": {"recordedDays":2,"state":"insufficientData"}
}
```

Add a four-day fixture where a prior `difficultToday` becomes `oneBite`; expected positive change is `시금치나물 한입도전`.

- [ ] **Step 2: Write failing Swift and Kotlin fixture tests**

Both tests load the same JSON and compare `recordedDays`, state, ordered nutrient IDs, and positive-change labels.

- [ ] **Step 3: Implement deterministic aggregation**

Sort by date then record ID, count distinct dates, group normalized menu names, and order nutrient misses by count descending then nutrient ID ascending. Do not calculate a score or percentile.

- [ ] **Step 4: Run both platform tests**

Run: `bash scripts/sync-native-rebuild-contracts.sh`

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/WeeklyReportBuilderTests"]`.

Run: `cd android && ./gradlew testDebugUnitTest --tests '*WeeklyReportBuilderTest'`

Expected: PASS with identical fixture outputs.

- [ ] **Step 5: Commit**

```bash
git add contracts/native-rebuild/v1/weekly-report-fixtures.json NaymNaymLevelUp/Rebuild/Parent/WeeklyReportBuilder.swift NaymNaymLevelUpTests/WeeklyReportBuilderTests.swift android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/WeeklyReportBuilder.kt android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent/WeeklyReportBuilderTest.kt
git commit -m "feat: define truthful weekly reports"
```

### Task 3: iOS 동기화 클라이언트와 대기열

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentSyncClient.swift`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentSyncQueue.swift`
- Create: `NaymNaymLevelUpTests/ParentSyncQueueTests.swift`
- Modify: `NaymNaymLevelUp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `ParentSyncClient.connect(inviteCode:) -> ParentSession`
- Produces: `ParentSyncClient.upsert(events:cursor:session:) -> SyncReceipt`
- Produces: `ParentSyncQueue.flush() async -> SyncRunResult`
- Consumes: Core Data `RebuildSyncEnvelope`

- [ ] **Step 1: Write failing retry and idempotency tests**

```swift
func testFailedUploadRemainsQueuedWithIncrementedRetry() async throws {
    let queue = ParentSyncQueue(store: .fixture, client: .failing(status: 503))
    let result = await queue.flush()
    XCTAssertEqual(result, .retryScheduled)
    XCTAssertEqual(try queue.store.envelope("event-1")?.retryCount, 1)
    XCTAssertEqual(try queue.store.envelope("event-1")?.state, .failed)
}
```

- [ ] **Step 2: Run the focused test**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/ParentSyncQueueTests"]`.

Expected: FAIL because the queue does not exist.

- [ ] **Step 3: Implement redacted requests and ordered flush**

```swift
struct ParentSession: Codable, Equatable {
    let childLinkID: UUID
    let parentSessionToken: String
}

enum SyncRunResult: Equatable {
    case nothingToDo
    case synced(count: Int)
    case retryScheduled
    case authenticationRequired
}
```

Store the parent session token in Keychain, not Core Data or UserDefaults. Select queued/failed envelopes ordered by `updatedAt`, upload at most 50, mark synced only after matching receipt IDs, and use exponential retry delays capped at 6 hours.

- [ ] **Step 4: Run queue and migration tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/ParentSyncQueueTests", "-only-testing:NaymNaymLevelUpTests/RebuildMigrationCoordinatorTests"]`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Parent/ParentSyncClient.swift NaymNaymLevelUp/Rebuild/Parent/ParentSyncQueue.swift NaymNaymLevelUpTests/ParentSyncQueueTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: add iOS parent sync queue"
```

### Task 4: Android 동기화 클라이언트와 대기열

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSyncClient.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSyncQueue.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSessionStore.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSyncQueueTest.kt`

**Interfaces:**
- Produces: Android equivalents of `ParentSession`, `SyncReceipt`, `SyncRunResult`
- Stores: session token in Android Keystore-backed encrypted storage

- [ ] **Step 1: Write the equivalent failing retry test**

Use a fake envelope DAO and failing client; assert retry count `1`, state `failed`, and local meal/progress rows unchanged.

- [ ] **Step 2: Run focused JVM test**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*ParentSyncQueueTest'`

Expected: FAIL because sync types do not exist.

- [ ] **Step 3: Implement queue and secure session storage**

Use a Keystore AES key with alias `naym-parent-session-v2`; store only encrypted token bytes in app-private preferences. Do not include tokens in exceptions, `toString`, or logs. Mirror the iOS ordering, 50-event batch, receipt matching, and retry cap.

- [ ] **Step 4: Run unit tests and debug build**

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent
git commit -m "feat: add Android parent sync queue"
```

### Task 5: iOS 부모 게이트와 `요약 · 기록 · 설정`

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Parent/GuardianGate.swift`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentNavigationView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentSummaryView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentHistoryView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentSettingsView.swift`
- Create: `NaymNaymLevelUp/Rebuild/Child/RebuildChildSettingsView.swift`
- Modify: `NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift`
- Create: `NaymNaymLevelUpTests/ParentPresentationTests.swift`

**Interfaces:**
- Produces: `GuardianGate` hold duration 2 seconds
- Produces: sensitive-action authentication through `LAContext`
- Consumes: `WeeklyReportBuilder`, `ParentSyncClient`, local repositories

- [ ] **Step 1: Write failing presentation tests**

Assert:

```swift
XCTAssertEqual(ParentCopy.weeklyState(recordedDays: 2), "확인할 기록이 조금 더 필요해요")
XCTAssertFalse(ParentPresentation.showsScore)
XCTAssertEqual(ParentPresentation.tabs, [.summary, .history, .settings])
```

- [ ] **Step 2: Run focused tests**

Run: XcodeBuildMCP `test_sim` with `extraArgs: ["-only-testing:NaymNaymLevelUpTests/ParentPresentationTests"]`.

Expected: FAIL.

- [ ] **Step 3: Implement calm report hierarchy**

Summary order:

1. child and sync status
2. today record completeness
3. weekly state or insufficient-data message
4. frequent nutrient possibilities with calculation note
5. positive changes and one or two alternative foods

History groups by date and clearly distinguishes `기록 없음` from `먹지 않았어요`. Parent settings contains connection, notification, export, delete, and privacy copy. `RebuildChildSettingsView` opens from the child home toolbar after `GuardianGate` and lets the parent update school and allergy codes through the existing onboarding components. Server URLs and internal identifiers are never shown.

- [ ] **Step 4: Verify Dynamic Type, VoiceOver, and device auth**

Run: XcodeBuildMCP `test_sim`.

Expected: PASS.

Inspect the three parent tabs at accessibility-extra-extra-extra-large. Verify reading order and that export/delete invokes LocalAuthentication before action.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Parent NaymNaymLevelUp/Rebuild/Foundation/RebuildRootView.swift NaymNaymLevelUpTests/ParentPresentationTests.swift NaymNaymLevelUp.xcodeproj/project.pbxproj
git commit -m "feat: build iOS parent experience"
```

### Task 6: Android 부모 게이트와 `요약 · 기록 · 설정`

**Files:**
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/GuardianGate.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentNavigation.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSummaryScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentHistoryScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentSettingsScreen.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/ChildSettingsScreen.kt`
- Modify: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentPresentationTest.kt`
- Create: `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentNavigationTest.kt`

**Interfaces:**
- Produces: Compose equivalents of the iOS parent tabs
- Uses: 2-second hold gate and `KeyguardManager.createConfirmDeviceCredentialIntent` for sensitive actions

- [ ] **Step 1: Write failing presentation and semantics tests**

Assert the same insufficient-data copy, no score label, exact tab order, visible sync timestamp, and device-credential launch callback for delete.

- [ ] **Step 2: Run focused tests**

Run: `cd android && ./gradlew testDebugUnitTest --tests '*ParentPresentationTest'`

Expected: FAIL.

- [ ] **Step 3: Implement the matched report hierarchy**

Use the same section order and copy rules as iOS. Use semantic headings, 48dp minimum actions, and do not encode nutrient state only with color. Add a child-home settings action that passes the 2-second guardian gate before opening `ChildSettingsScreen` for school/allergy updates. The settings delete action stays disabled until device credential success callback.

- [ ] **Step 4: Run unit and instrumentation tests**

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/ui/RebuildApp.kt android/app/src/test android/app/src/androidTest
git commit -m "feat: build Android parent experience"
```

### Task 7: CloudKit 전환·내보내기·삭제

**Files:**
- Create: `NaymNaymLevelUp/Rebuild/Parent/LegacyParentLinkTransition.swift`
- Create: `NaymNaymLevelUpTests/LegacyParentLinkTransitionTests.swift`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentDataExporter.kt`
- Create: `NaymNaymLevelUp/Rebuild/Parent/ParentDataExporter.swift`
- Modify: `supabase/functions/parent-sync/v2-sync.ts`
- Modify: `supabase/functions/parent-sync/v2-sync_test.ts`
- Create: `docs/qa/parent-data-lifecycle.md`

**Interfaces:**
- Produces transition states: `notNeeded`, `serverSessionReady`, `relinkRequired`, `failedWithoutDataLoss`
- Produces export: local JSON with profile, meal records, progress events, connection metadata; excludes secrets
- Produces deletion receipt with local/server outcomes separated

- [ ] **Step 1: Write failing transition and deletion tests**

Test that a connected CloudKit link without a v2 session returns `relinkRequired`, keeps local records, and never uploads CloudKit record IDs. Test server deletion revokes sessions before deleting event payloads.

- [ ] **Step 2: Implement safe transition and export**

Export JSON keys:

```json
{
  "exportVersion": 1,
  "profile": {},
  "mealRecords": [],
  "progressEvents": [],
  "connection": {"state": "connected", "lastSyncedAt": null}
}
```

Do not include invite secrets, session tokens, device tokens, server URLs, or CloudKit record names.

- [ ] **Step 3: Implement ordered deletion**

Server order: authenticate session → revoke all link sessions → write deletion audit without meal payload → delete event payloads → return receipt. Client order: obtain device credential → request server deletion → show separate server result → delete local rebuild database only after explicit second confirmation. Legacy source stores remain until the release-readiness plan's retention gate.

- [ ] **Step 4: Run server and platform suites**

Run: `deno test supabase/functions/parent-sync/*_test.ts`

Run: XcodeBuildMCP `test_sim`.

Run: `cd android && ./gradlew testDebugUnitTest connectedDebugAndroidTest assembleDebug`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add NaymNaymLevelUp/Rebuild/Parent NaymNaymLevelUpTests android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent supabase/functions/parent-sync docs/qa/parent-data-lifecycle.md
git commit -m "feat: finish protected parent data lifecycle"
```

### Task 8: 부모 알림의 iOS APNs·Android FCM 동등성

**Files:**
- Modify: `supabase/migrations/20260725_parent_sync_v2.sql`
- Modify: `supabase/functions/parent-sync/v2-sync.ts`
- Modify: `supabase/functions/parent-sync/v2-sync_test.ts`
- Modify: `android/app/build.gradle`
- Modify: `android/README.md`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentMessagingService.kt`
- Create: `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentNotificationRegistrar.kt`
- Create: `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/parent/ParentNotificationRegistrarTest.kt`
- Modify: iOS parent notification registration adapter
- Create: `docs/qa/parent-notification-privacy.md`

**Interfaces:**
- Produces device platforms: `apnsSandbox`, `apnsProduction`, `fcm`
- Produces generic lock-screen copy: `새 급식 기록이 도착했어요`
- Guarantees: menu name, eating status, nutrient, child school, and tokens are absent from notification payload and logs

- [ ] **Step 1: Write failing server and client tests**

Server test asserts one APNs and one FCM device receive platform-specific send calls but the same generic title/body. Android test asserts token registration occurs only in parent mode with explicit notification permission.

- [ ] **Step 2: Add Messaging-only Firebase dependencies**

Use Messaging without Analytics and initialize it from build configuration rather than a checked-in `google-services.json`:

```groovy
// app build.gradle
implementation platform("com.google.firebase:firebase-bom:34.16.0")
implementation "com.google.firebase:firebase-messaging"

buildConfigField "String", "FIREBASE_APPLICATION_ID", quoteBuildConfig(localProperties.getProperty("FIREBASE_APPLICATION_ID", ""))
buildConfigField "String", "FIREBASE_API_KEY", quoteBuildConfig(localProperties.getProperty("FIREBASE_API_KEY", ""))
buildConfigField "String", "FIREBASE_PROJECT_ID", quoteBuildConfig(localProperties.getProperty("FIREBASE_PROJECT_ID", ""))
buildConfigField "String", "FIREBASE_SENDER_ID", quoteBuildConfig(localProperties.getProperty("FIREBASE_SENDER_ID", ""))
```

Do not add Firebase Analytics, Crashlytics, Performance, Remote Config, AdMob, or App Check in this task. Document the four local properties in `android/README.md`; never print their values.

- [ ] **Step 3: Implement token registration and generic delivery**

Create `FirebaseOptions` from the four non-empty BuildConfig values and initialize the default Firebase app only when parent notifications are enabled. Request Android notification permission only after the parent chooses `알림 받기`. Register `fcm` devices through v2 sync. Server FCM HTTP v1 credentials use `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, and `FCM_PRIVATE_KEY`; never return them to clients.

Store token rows with restricted service-role access. On disconnect or data deletion, revoke the device row. Notification payload contains only route `parentSummary` and a generic localized message.

- [ ] **Step 4: Run tests and inspect merged manifest**

Run: `deno test supabase/functions/parent-sync/*_test.ts`

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Run: `cd android && ./gradlew processDebugMainManifest`

Expected: PASS, no Analytics component, and no `com.google.android.gms.permission.AD_ID` in the merged manifest.

- [ ] **Step 5: Verify privacy behavior**

Trigger a test notification with the device locked. Confirm no child-specific meal information appears. Disable notifications in parent settings and confirm the server registration is revoked.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260725_parent_sync_v2.sql supabase/functions/parent-sync android/app/build.gradle android/README.md android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/parent android/app/src/test docs/qa/parent-notification-privacy.md NaymNaymLevelUp/Rebuild/Parent
git commit -m "feat: add private cross-platform parent alerts"
```
