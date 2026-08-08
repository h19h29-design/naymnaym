# 앱인토스 급식 없음 회복 경험 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 급식이 없는 날에도 현재 성장 캐릭터, 가장 가까운 다음 급식, 주간 급식표와 학교 변경 행동을 제공한다.

**Architecture:** 오늘 급식이 `NO_DATA`일 때만 `useNextMeal` 훅이 향후 7일의 평일을 가까운 날짜부터 조회한다. `TodayPage`는 일반 급식 화면과 분리된 `NoMealState`를 렌더링하고, `MealSchedulePage`는 `mode=weekly` 쿼리로 주간 보기를 바로 연다.

**Tech Stack:** React 18, TypeScript 5, React Router 7, Vitest 4, Testing Library, Apps-in-Toss Web Framework, 기존 Supabase Edge Function 및 NEIS 계약.

## Global Constraints

- 실제 급식, 저장된 급식, 체험 급식, 급식 없음, 조회 오류를 계속 분리해서 표시한다.
- 실제 급식 조회 실패를 체험 급식으로 자동 전환하지 않는다.
- 새 서버, Supabase DB·Auth·Storage·Realtime, 유료 기능 또는 사용자 서버 저장소를 추가하지 않는다.
- 오늘 급식이 `NO_DATA`인 경우에만 기존 NEIS 중계 함수를 최대 5회 추가 호출한다.
- 향후 7일의 토요일·일요일은 조회하지 않으며, 공휴일이나 학교 사유를 임의로 단정하지 않는다.
- 다음 급식의 성공 결과는 기존 기기 캐시에만 저장하고, 캐시 쓰기 실패는 화면을 막지 않는다.
- 실제 화면에는 현재 레벨 이미지와 누적 XP가 항상 보이며, 급식이 없을 때 비활성 기록 버튼을 남기지 않는다.
- 기존 `.superpowers/sdd/task-5-report.md`, `.superpowers/sdd/task-6-report.md` 변경은 다른 작업의 것이므로 커밋하지 않는다.

---

## File Structure

```text
apps-in-toss/src/
├── features/today/useNextMeal.ts            # 다음 평일 급식 후보·조회·캐시·재시도
├── features/today/useNextMeal.test.ts       # 순차 조회·오류·캐시 계약
├── features/today/NoMealState.tsx           # 캐릭터 중심의 급식 없음 회복 화면
├── features/today/NoMealState.test.tsx      # 화면 상태와 행동 검증
├── features/today/TodayPage.tsx             # noMeal 상태 연결
├── features/today/TodayPage.test.tsx        # TodayPage 회귀 테스트
├── features/meals/MealSchedulePage.tsx      # mode=weekly 초기 상태 지원
├── app/App.test.tsx                         # 주간 급식표 딥링크 검증
└── styles/global.css                        # 회복 카드와 다음 급식 미리보기 스타일
```

### Task 1: 다음 급식 조회 계약

**Files:**
- Create: `apps-in-toss/src/features/today/useNextMeal.ts`
- Create: `apps-in-toss/src/features/today/useNextMeal.test.ts`

**Interfaces:**
- Consumes: `MealDay`, `Profile`, `NeisClient`, `AppRepository`, `seoulDate`, `isValidLiveMeal`.
- Produces: `nextMealCandidateDates`, `loadNextMeal`, `useNextMeal`, `NextMealResult`.
- Consumed by: `TodayPage`, `NoMealState`.

- [ ] **Step 1: 후보 날짜와 로더의 실패 테스트를 작성한다.**

```ts
it('skips weekend dates and searches the closest weekday first', () => {
  expect(nextMealCandidateDates(new Date('2026-08-07T15:00:00.000Z')))
    .toEqual(['20260810', '20260811', '20260812', '20260813', '20260814']);
});

it('continues after NO_DATA and stops after the first valid meal', async () => {
  const fetchMeal = vi.fn()
    .mockRejectedValueOnce(new NeisClientError('NO_DATA', '없음', 404))
    .mockResolvedValueOnce({ ...meal, date: '20260811' });
  const result = await loadNextMeal({ profile: makeProfile(), client: { fetchMeal } as never,
    repository: { cacheMeal: vi.fn() } as never, now: new Date('2026-08-08T15:00:00.000Z') });
  expect(result).toEqual({ kind: 'live', meal: { ...meal, date: '20260811' } });
  expect(fetchMeal).toHaveBeenCalledTimes(2);
});
```

- [ ] **Step 2: 테스트가 구현 부재로 실패하는지 확인한다.**

Run: `npm test -- --run src/features/today/useNextMeal.test.ts`

Expected: FAIL because `useNextMeal.ts` does not exist.

- [ ] **Step 3: 최소 조회 구현을 작성한다.**

```ts
export type NextMealResult =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'live'; meal: MealDay }
  | { kind: 'cache'; meal: MealDay }
  | { kind: 'notFound' }
  | { kind: 'error'; code: string };

export function nextMealCandidateDates(now = new Date()): string[] {
  const start = parseDateKey(seoulDate(now));
  return Array.from({ length: 7 }, (_, offset) => addDays(start, offset + 1))
    .filter((date) => date.getUTCDay() !== 0 && date.getUTCDay() !== 6)
    .map(dateKey);
}
```

For each candidate call `client.fetchMeal`. Continue only for `NeisClientError` code `NO_DATA`; return the first valid non-sample exact-date meal; use an exact-date cache after another error; cache live success without allowing cache failure to reject it. `useNextMeal` owns `AbortController`, returns `idle` without a request when `active` is false, and exposes `retry` by incrementing an attempt counter.

- [ ] **Step 4: 전부 없음·오류·정확한 캐시·취소 테스트를 추가해 통과시킨다.**

```ts
expect(await loadNextMeal(noDataEveryWeekday)).toEqual({ kind: 'notFound' });
expect(await loadNextMeal(networkFailure)).toEqual({ kind: 'error', code: 'UPSTREAM_ERROR' });
expect(await loadNextMeal(cachedFailure)).toEqual({ kind: 'cache', meal: cachedMeal });
expect(cacheMeal).not.toHaveBeenCalled(); // cache result
```

Run: `npm test -- --run src/features/today/useNextMeal.test.ts`

Expected: PASS.

- [ ] **Step 5: 이 독립 계약을 커밋한다.**

```bash
git add apps-in-toss/src/features/today/useNextMeal.ts apps-in-toss/src/features/today/useNextMeal.test.ts
git commit -m "feat: find the next available school meal"
```

### Task 2: 캐릭터 중심 급식 없음 상태

**Files:**
- Create: `apps-in-toss/src/features/today/NoMealState.tsx`
- Create: `apps-in-toss/src/features/today/NoMealState.test.tsx`
- Modify: `apps-in-toss/src/styles/global.css`

**Interfaces:**
- Consumes: `Level`, `NextMealResult`, `MealItem`, `allergyRisk`, `ALLERGIES`.
- Produces: `NoMealState` with `onRetryToday`, `onRetryNext`, `onOpenWeekly`, `onEditSchool` callbacks.
- Consumed by: `TodayPage`.

- [ ] **Step 1: 회복 화면의 실패 테스트를 작성한다.**

```tsx
render(<NoMealState level={levelFor(150)} totalXp={150} allergyCodes={[6]}
  nextMeal={{ kind: 'live', meal: mealWithAllergen(6) }} {...handlers} />);

expect(screen.getByRole('img', { name: /레벨 2/ })).toBeInTheDocument();
expect(screen.getByText('오늘은 급식이 없는 날이에요')).toBeInTheDocument();
expect(screen.getByText('다음 급식')).toBeInTheDocument();
expect(screen.getByText('알레르기 안전을 먼저 확인해 주세요 · 밀')).toBeInTheDocument();
await user.click(screen.getByRole('button', { name: '주간 급식표 보기' }));
expect(handlers.onOpenWeekly).toHaveBeenCalledOnce();
```

- [ ] **Step 2: 테스트가 컴포넌트 부재로 실패하는지 확인한다.**

Run: `npm test -- --run src/features/today/NoMealState.test.tsx`

Expected: FAIL because `NoMealState.tsx` does not exist.

- [ ] **Step 3: 기록 행동이 없는 회복 화면을 구현한다.**

```tsx
export function NoMealState({ level, totalXp, allergyCodes, nextMeal, onRetryToday, onRetryNext, onOpenWeekly, onEditSchool }: Props) {
  return <section className="forest-card no-meal-recovery" aria-label="급식 없음 안내">
    <img src={'/growth/level-' + level.number + '.png'} alt={'레벨 ' + level.number + ' ' + level.title + ' 캐릭터'} />
    <p className="forest-eyebrow">레벨 {level.number} · 총 {totalXp} XP</p>
    <h2>오늘은 급식이 없는 날이에요</h2>
    <p>다람쥐도 잠깐 쉬어가요!</p>
    <NextMealPreview result={nextMeal} allergyCodes={allergyCodes} onRetry={onRetryNext} />
    <div className="no-meal-recovery__actions">
      <button type="button" onClick={onOpenWeekly}>주간 급식표 보기</button>
      <button type="button" onClick={onRetryToday}>다시 확인</button>
    </div>
    {nextMeal.kind === 'notFound' ? <button type="button" onClick={onEditSchool}>학교 설정 확인</button> : null}
  </section>;
}
```

`NextMealPreview`는 `loading`, `live`, `cache`, `notFound`, `error`를 `role="status"` 또는 `role="alert"`로 나눈다. 실제·캐시 메뉴에는 날짜, 칼로리, 메뉴 목록, 알레르기 안내만 표시하고 기록 버튼은 렌더링하지 않는다.

- [ ] **Step 4: 숲 배경의 대비를 유지하는 스타일을 추가한다.**

```css
.no-meal-recovery { padding: 24px; border-radius: 28px; text-align: center; }
.no-meal-recovery > img { width: min(68vw, 248px); margin: 0 auto 12px; }
.no-meal-recovery__next { margin-top: 20px; padding: 18px; border-radius: 20px; background: rgba(203, 234, 120, 0.22); text-align: left; }
.no-meal-recovery__actions { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 18px; }
```

Use existing `--forest-*`, `--cream-*`, and `.forest-card` tokens; add no global color token.

- [ ] **Step 5: 모든 상태와 접근성 테스트를 통과시킨다.**

Add tests for `loading`, `cache`, `notFound`, and `error`; assert `notFound` shows `학교 설정 확인`, error shows `다음 급식 다시 시도`, and no state renders `오늘 급식 기록하기`.

Run: `npm test -- --run src/features/today/NoMealState.test.tsx`

Expected: PASS.

- [ ] **Step 6: 회복 화면을 커밋한다.**

```bash
git add apps-in-toss/src/features/today/NoMealState.tsx apps-in-toss/src/features/today/NoMealState.test.tsx apps-in-toss/src/styles/global.css
git commit -m "feat: add character-first no-meal recovery state"
```

### Task 3: 오늘 화면 연결

**Files:**
- Modify: `apps-in-toss/src/features/today/TodayPage.tsx`
- Modify: `apps-in-toss/src/features/today/TodayPage.test.tsx`
- Modify: `apps-in-toss/src/features/today/TodayPage.integration.test.tsx` only if the existing client mock must isolate `useNextMeal`.

**Interfaces:**
- Consumes: `useNextMeal`, `NoMealState`, `useTodayMeal`, React Router `useNavigate`.
- Produces: `noMeal` branch without a disabled meal-recording action.
- Consumed by: `/today` and `/today?demo=1`.

- [ ] **Step 1: TodayPage 통합 실패 테스트를 추가한다.**

```tsx
it('replaces the disabled record action with the grown character recovery state', async () => {
  renderToday({ mealResult: { kind: 'noMeal' } });
  useNextMeal.mockReturnValue({ result: { kind: 'notFound' }, retry: vi.fn() });
  renderPage();
  expect(await screen.findByRole('img', { name: /레벨 1/ })).toBeInTheDocument();
  expect(screen.getByRole('button', { name: '주간 급식표 보기' })).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: '오늘은 기록할 급식이 없어요' })).not.toBeInTheDocument();
});
```

- [ ] **Step 2: 테스트가 새 훅·회복 화면 연결 부재로 실패하는지 확인한다.**

Run: `npm test -- --run src/features/today/TodayPage.test.tsx`

Expected: FAIL until `TodayPage` renders `NoMealState`.

- [ ] **Step 3: noMeal일 때만 다음 급식을 조회하고 회복 화면을 렌더링한다.**

```tsx
const navigate = useNavigate();
const nextMeal = useNextMeal({
  active: sessionMode.kind === 'live' && profile !== null && result !== 'loading' && result.kind === 'noMeal',
  profile, client: neisClient, repository,
});

if (result !== 'loading' && result.kind === 'noMeal') {
  return <ForestScene className="today-page" showSettings>
    <header className="forest-title-card"><h1>오늘 급식</h1><p>{dateText}</p></header>
    <NoMealState level={level} totalXp={progress.totalXp} allergyCodes={profile?.allergyCodes ?? []}
      nextMeal={nextMeal.result} onRetryToday={retry} onRetryNext={nextMeal.retry}
      onOpenWeekly={() => navigate('/meals?mode=weekly')}
      onEditSchool={() => navigate('/onboarding?mode=edit&next=%2Ftoday')} />
    <ForestNavigation />
  </ForestScene>;
}
```

Keep the existing character stage, meal list, recording sheet, cache label, demo mode, error state, and save retry path unchanged for all other `TodayMealResult` values.

- [ ] **Step 4: TodayPage 회귀·통합 테스트를 통과시킨다.**

Mock `useNextMeal` with `{ result: { kind: 'idle' }, retry: vi.fn() }` in `TodayPage.test.tsx` except for no-meal tests.

Run: `npm test -- --run src/features/today/TodayPage.test.tsx src/features/today/TodayPage.integration.test.tsx`

Expected: PASS.

- [ ] **Step 5: 오늘 화면 연결을 커밋한다.**

```bash
git add apps-in-toss/src/features/today/TodayPage.tsx apps-in-toss/src/features/today/TodayPage.test.tsx apps-in-toss/src/features/today/TodayPage.integration.test.tsx
git commit -m "feat: guide no-meal users to the next school lunch"
```

### Task 4: 주간 급식표 딥링크

**Files:**
- Modify: `apps-in-toss/src/features/meals/MealSchedulePage.tsx`
- Modify: `apps-in-toss/src/app/App.test.tsx`

**Interfaces:**
- Consumes: `useSearchParams` and `ScheduleMode`.
- Produces: `/meals?mode=weekly` that renders `주간 급식표` immediately.
- Consumed by: `NoMealState` weekly-action callback.

- [ ] **Step 1: 쿼리 기반 주간 보기 실패 테스트를 추가한다.**

```tsx
it('opens the weekly schedule directly from a no-meal recovery link', async () => {
  renderTestApp({ initialEntry: '/meals?demo=1&mode=weekly', profile: makeProfile() });
  expect(await screen.findByLabelText('주간 급식표')).toBeInTheDocument();
  expect(screen.queryByLabelText('일간 급식표')).not.toBeInTheDocument();
});
```

- [ ] **Step 2: 테스트가 일간 기본값 때문에 실패하는지 확인한다.**

Run: `npm test -- --run src/app/App.test.tsx`

Expected: FAIL because `MealSchedulePage` always starts with `daily`.

- [ ] **Step 3: 허용된 쿼리 값만 초기 상태에 반영한다.**

```tsx
const [searchParams] = useSearchParams();
const requestedMode = searchParams.get('mode');
const initialMode: ScheduleMode = requestedMode === 'weekly' || requestedMode === 'monthly' || requestedMode === 'daily'
  ? requestedMode : 'daily';
const [mode, setMode] = useState<ScheduleMode>(initialMode);
```

Keep `demo=1` handling unchanged; `mode=invalid` must render daily view.

- [ ] **Step 4: 딥링크와 기존 보기 전환 테스트를 통과시킨다.**

Run: `npm test -- --run src/app/App.test.tsx`

Expected: PASS.

- [ ] **Step 5: 딥링크 지원을 커밋한다.**

```bash
git add apps-in-toss/src/features/meals/MealSchedulePage.tsx apps-in-toss/src/app/App.test.tsx
git commit -m "feat: open meal schedules in the requested view"
```

### Task 5: 전체 검증과 Apps-in-Toss 테스트 배포

**Files:**
- Modify only if verification exposes a defect in files from Tasks 1–4.
- Do not modify: `.superpowers/sdd/task-5-report.md`, `.superpowers/sdd/task-6-report.md`.

**Interfaces:**
- Consumes: completed recovery UI, test suite, Vite build, Apps-in-Toss bundle tooling.
- Produces: verified `.ait` bundle and newly registered Toss test deployment.

- [ ] **Step 1: 변경 범위와 유형 검사를 실행한다.**

```bash
git status --short
npm run typecheck
npm test -- --run
```

Expected: only feature files and the pre-existing SDD report files are dirty; TypeScript and Vitest pass.

- [ ] **Step 2: 웹 번들과 릴리스 제약을 검증한다.**

```bash
npm run build:web
npm run verify:web
npm run build:ait
npm run verify:release
```

Expected: web build, `.ait` build, bundle-size, and release verification pass.

- [ ] **Step 3: 새 테스트 번들을 토스 콘솔에 등록한다.**

In the existing `러쉬윈드` Chrome profile, register the built `.ait` bundle as a new Apps-in-Toss test version and open its QR code. Do not request marketplace review; this task produces a test deployment only.

- [ ] **Step 4: 실제 QR 흐름을 확인한다.**

1. `NO_DATA` 날짜에서 현재 레벨 캐릭터와 XP가 보인다.
2. 비활성 급식 기록 버튼이 남아 있지 않다.
3. 다음 급식 미리보기 또는 명시적인 다음 급식 오류가 보인다.
4. `주간 급식표 보기`가 주간 모드를 연다.
5. `다시 확인`이 오늘 급식 조회를 재시도한다.
6. 정상 실제 급식과 체험 급식이 기존대로 동작한다.

- [ ] **Step 5: 구현 커밋을 푸시한다.**

```bash
git add apps-in-toss/src/features/today/useNextMeal.ts apps-in-toss/src/features/today/useNextMeal.test.ts apps-in-toss/src/features/today/NoMealState.tsx apps-in-toss/src/features/today/NoMealState.test.tsx apps-in-toss/src/features/today/TodayPage.tsx apps-in-toss/src/features/today/TodayPage.test.tsx apps-in-toss/src/features/today/TodayPage.integration.test.tsx apps-in-toss/src/features/meals/MealSchedulePage.tsx apps-in-toss/src/app/App.test.tsx apps-in-toss/src/styles/global.css
git commit -m "feat: improve no-meal experience"
git push origin codex/apps-in-toss-mvp
```

Report the test deployment version and QR status to the user. Keep marketplace review separate from the test deployment.
