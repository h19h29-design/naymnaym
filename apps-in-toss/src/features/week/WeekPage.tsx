import { useCallback, useEffect, useMemo, useState } from 'react';
import { formatKoreanDate, getSeoulDateKey, weekKeys } from '../../domain/date';
import { hasAllergyRisk } from '../../domain/allergy';
import type { MealDay } from '../../domain/types';
import { useAppState } from '../../state/AppStateProvider';
import { clientErrorMessage } from '../../services/neisClient';

export function WeekPage() {
  const { state, client } = useAppState();
  const school = state.profile!.school;
  const today = getSeoulDateKey();
  const keys = useMemo(() => weekKeys(today), [today]);
  const [meals, setMeals] = useState<MealDay[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try { setMeals(await client.fetchMealsRange({ officeCode: school.officeCode, schoolCode: school.schoolCode, fromDate: keys[0], toDate: keys[6] })); }
    catch (cause) { setError(clientErrorMessage(cause)); }
    finally { setLoading(false); }
  }, [client, keys, school.officeCode, school.schoolCode]);
  useEffect(() => { void load(); }, [load]);
  return <main className="page with-tabs"><header className="page-header"><div><p className="eyebrow">{school.name}</p><h1>이번 주 급식</h1><p>이번 주 월요일부터 일요일까지 보여드려요.</p></div></header>
    {loading && <section className="state-card" aria-live="polite">일주일 급식을 불러오는 중이에요…</section>}
    {error && <section className="state-card"><h2>주간 급식을 불러오지 못했어요</h2><p>{error}</p><button className="primary" onClick={() => void load()}>다시 시도</button></section>}
    {!loading && !error && <div className="week-list">{keys.map((key) => {
      const meal = meals.find((entry) => entry.date === key);
      const risky = meal?.menuItems.some((item) => hasAllergyRisk(item.allergyCodes, state.profile!.allergyCodes));
      return <details key={key} data-testid="week-day" className={key === today ? 'today' : ''} open={key === today}>
        <summary><span><strong>{formatKoreanDate(key)}</strong>{key === today && <em>오늘</em>}</span><span>{meal?.menuItems[0]?.name ?? '급식이 없어요'}</span></summary>
        {meal ? <><ul>{meal.menuItems.map((item) => <li key={item.id}>{item.name}{hasAllergyRisk(item.allergyCodes, state.profile!.allergyCodes) && <span className="risk-badge">주의</span>}</li>)}</ul>{risky && <p className="safety-message">알레르기 가능 메뉴가 있어요. 학교 안내와 보호자 확인이 먼저예요.</p>}</> : <p>급식이 없어요</p>}
      </details>;
    })}</div>}
  </main>;
}
