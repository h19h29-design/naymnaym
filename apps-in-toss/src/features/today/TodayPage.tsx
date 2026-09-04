import { Button } from '@toss/tds-mobile';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { GrowthCard } from '../../components/GrowthCard';
import { recordIdentity } from '../../domain/progress';
import { formatKoreanDate, getSeoulDateKey } from '../../domain/date';
import { hasAllergyRisk } from '../../domain/allergy';
import type { MealDay } from '../../domain/types';
import { NeisClientError, clientErrorMessage } from '../../services/neisClient';
import { useAppState } from '../../state/AppStateProvider';
import { MealCard } from './MealCard';
import { demoMeal } from './demoMeal';

type ViewState = { kind: 'loading' } | { kind: 'meal'; meal: MealDay; source: 'live' | 'cache' | 'demo'; warning?: string } | { kind: 'empty' } | { kind: 'error'; message: string };

export function TodayPage() {
  const { state, client, cacheMeal, recordMeal } = useAppState();
  const profile = state.profile!;
  const date = getSeoulDateKey();
  const cacheKey = `${profile.school.officeCode}|${profile.school.schoolCode}|${date}`;
  const [view, setView] = useState<ViewState>({ kind: 'loading' });
  const [feedback, setFeedback] = useState(false);
  const cacheRef = useRef(state.cache);

  useEffect(() => { cacheRef.current = state.cache; }, [state.cache]);

  const load = useCallback(async () => {
    setView({ kind: 'loading' });
    try {
      const meal = await client.fetchMeals({ officeCode: profile.school.officeCode, schoolCode: profile.school.schoolCode, date });
      setView({ kind: 'meal', meal, source: 'live' });
      cacheRef.current = { key: cacheKey, meal, savedAt: Date.now() };
      void cacheMeal(cacheKey, meal).catch(() => undefined);
    } catch (error) {
      if (error instanceof NeisClientError && error.kind === 'NO_DATA') { setView({ kind: 'empty' }); return; }
      if (cacheRef.current?.key === cacheKey) setView({ kind: 'meal', meal: cacheRef.current.meal, source: 'cache', warning: clientErrorMessage(error) });
      else setView({ kind: 'error', message: clientErrorMessage(error) });
    }
  }, [cacheKey, cacheMeal, client, date, profile.school.officeCode, profile.school.schoolCode]);

  useEffect(() => { void load(); }, [load]);

  return <main className="page with-tabs">
    <header className="page-header"><div><p className="eyebrow">{profile.school.name}</p><h1>오늘의 급식</h1><p>{formatKoreanDate(date)}</p></div><Link className="text-link" to="/onboarding">학교·알레르기 수정</Link></header>
    <GrowthCard totalXP={state.totalXP} />
    {feedback && <p className="growth-feedback" role="status">기록했어요! XP가 새 상태로 반영됐어요.</p>}
    {view.kind === 'loading' && <section className="state-card" aria-live="polite"><span className="spinner" />급식을 불러오는 중이에요…</section>}
    {view.kind === 'empty' && <StateCard title="오늘은 급식이 없어요" body="학교 일정이나 휴일일 수 있어요." retry={load} demo={() => setView({ kind: 'meal', meal: demoMeal(date), source: 'demo' })} />}
    {view.kind === 'error' && <StateCard title="급식을 불러오지 못했어요" body={view.message} retry={load} demo={() => setView({ kind: 'meal', meal: demoMeal(date), source: 'demo' })} />}
    {view.kind === 'meal' && <section aria-labelledby="meal-title">
      <div className="section-heading"><div><p className={`source-badge ${view.source}`}>{view.source === 'live' ? '학교 급식' : view.source === 'cache' ? '저장된 급식' : '체험 급식'}</p><h2 id="meal-title">{formatKoreanDate(view.meal.date)} 메뉴</h2></div><div className="section-actions"><Button color="light" onClick={() => void load()}>급식 새로고침</Button><Link to="/week">일주일 보기 →</Link></div></div>
      {view.warning && <p className="warning" role="status">{view.warning} 저장된 급식을 보여드려요.</p>}
      {view.source === 'demo' && <p className="demo-note">체험 급식의 선택과 XP는 저장되지 않아요.</p>}
      <div className="meal-list">{view.meal.menuItems.map((item) => {
        const record = state.mealRecords.find((entry) => entry.identity === recordIdentity(view.meal.date, item.name));
        return <MealCard key={item.id} item={item} risky={hasAllergyRisk(item.allergyCodes, profile.allergyCodes)} selected={record?.status} onStatus={(status) => { if (view.source !== 'demo') void recordMeal(view.meal.date, item.name, status).then(() => setFeedback(true)); }} />;
      })}</div>
    </section>}
  </main>;
}

function StateCard({ title, body, retry, demo }: { title: string; body: string; retry: () => Promise<void>; demo: () => void }) {
  return <section className="state-card"><h2>{title}</h2><p>{body}</p><div className="button-row"><Button onClick={() => void retry()}>다시 시도</Button><Button color="light" onClick={demo}>체험 급식 보기</Button></div></section>;
}
