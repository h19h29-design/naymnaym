import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { GrowthCard } from '../../components/GrowthCard';
import { formatKoreanDate, getSeoulDateKey } from '../../domain/date';
import { hasAllergyRisk } from '../../domain/allergy';
import type { MealDay } from '../../domain/types';
import { NeisClientError } from '../../services/neisClient';
import { useAppState } from '../../state/AppStateProvider';
import { MealCard } from './MealCard';
import { demoMeal } from './demoMeal';

type ViewState = { kind: 'loading' } | { kind: 'meal'; meal: MealDay; source: 'live' | 'cache' | 'demo'; warning?: string } | { kind: 'empty' } | { kind: 'error'; message: string };

function errorMessage(error: unknown) {
  const kind = error instanceof NeisClientError ? error.kind : 'NETWORK';
  if (kind === 'NOT_CONFIGURED' || kind === 'UPSTREAM_ERROR' || kind === 'INVALID_RESPONSE') return '급식 서버를 점검하고 있어요. 잠시 후 다시 시도해 주세요.';
  if (kind === 'FORBIDDEN_ORIGIN') return '허용된 토스 앱 환경에서 다시 열어 주세요.';
  if (kind === 'RATE_LIMITED') return '요청이 많아요. 잠시 쉬었다 다시 시도해 주세요.';
  return '네트워크 연결을 확인하고 다시 시도해 주세요.';
}

export function TodayPage() {
  const { state, client, cacheMeal, recordMeal } = useAppState();
  const profile = state.profile!;
  const date = getSeoulDateKey();
  const cacheKey = `${profile.school.officeCode}|${profile.school.schoolCode}|${date}`;
  const [view, setView] = useState<ViewState>({ kind: 'loading' });

  const load = useCallback(async () => {
    setView({ kind: 'loading' });
    try {
      const meal = await client.fetchMeals({ officeCode: profile.school.officeCode, schoolCode: profile.school.schoolCode, date });
      setView({ kind: 'meal', meal, source: 'live' });
      await cacheMeal(cacheKey, meal);
    } catch (error) {
      if (error instanceof NeisClientError && error.kind === 'NO_DATA') { setView({ kind: 'empty' }); return; }
      if (state.cache?.key === cacheKey) setView({ kind: 'meal', meal: state.cache.meal, source: 'cache', warning: errorMessage(error) });
      else setView({ kind: 'error', message: errorMessage(error) });
    }
  }, [cacheKey, cacheMeal, client, date, profile.school.officeCode, profile.school.schoolCode]);

  useEffect(() => { void load(); }, [load]);

  return <main className="page with-tabs">
    <header className="page-header"><div><p className="eyebrow">{profile.school.name}</p><h1>오늘의 급식</h1><p>{formatKoreanDate(date)}</p></div><Link className="text-link" to="/onboarding">학교·알레르기 수정</Link></header>
    <GrowthCard totalXP={state.totalXP} />
    {view.kind === 'loading' && <section className="state-card" aria-live="polite"><span className="spinner" />급식을 불러오는 중이에요…</section>}
    {view.kind === 'empty' && <StateCard title="오늘은 급식이 없어요" body="학교 일정이나 휴일일 수 있어요." retry={load} demo={() => setView({ kind: 'meal', meal: demoMeal(date), source: 'demo' })} />}
    {view.kind === 'error' && <StateCard title="급식을 불러오지 못했어요" body={view.message} retry={load} demo={() => setView({ kind: 'meal', meal: demoMeal(date), source: 'demo' })} />}
    {view.kind === 'meal' && <section aria-labelledby="meal-title">
      <div className="section-heading"><div><p className={`source-badge ${view.source}`}>{view.source === 'live' ? '학교 급식' : view.source === 'cache' ? '저장된 급식' : '체험 급식'}</p><h2 id="meal-title">{formatKoreanDate(view.meal.date)} 메뉴</h2></div><Link to="/week">일주일 보기 →</Link></div>
      {view.warning && <p className="warning" role="status">{view.warning} 저장된 급식을 보여드려요.</p>}
      {view.source === 'demo' && <p className="demo-note">체험 급식의 선택과 XP는 저장되지 않아요.</p>}
      <div className="meal-list">{view.meal.menuItems.map((item) => {
        const record = state.mealRecords.find((entry) => entry.identity === `${view.meal.date}|${item.name.trim()}`);
        return <MealCard key={item.id} item={item} risky={hasAllergyRisk(item.allergyCodes, profile.allergyCodes)} selected={record?.status} onStatus={(status) => { if (view.source !== 'demo') void recordMeal(view.meal.date, item.name, status); }} />;
      })}</div>
    </section>}
  </main>;
}

function StateCard({ title, body, retry, demo }: { title: string; body: string; retry: () => Promise<void>; demo: () => void }) {
  return <section className="state-card"><h2>{title}</h2><p>{body}</p><div className="button-row"><button className="primary" onClick={() => void retry()}>다시 시도</button><button onClick={demo}>체험 급식 보기</button></div></section>;
}
