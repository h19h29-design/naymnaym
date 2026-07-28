import { useEffect, useMemo, useState } from 'react';
import type { MealDay, MealItem } from '@nyam/neis-contract';
import { useSearchParams } from 'react-router-dom';
import { ForestNavigation } from '../../components/ForestNavigation';
import { ForestScene } from '../../components/ForestScene';
import { NeisClientError, neisClient } from '../../services/neisClient';
import { useAppState } from '../../state/AppStateProvider';
import { seoulDate } from '../today/useTodayMeal';

type ScheduleMode = 'daily' | 'weekly' | 'monthly';
type ScheduleMeals = Record<string, MealDay | null>;
type ScheduleState =
  | { status: 'loading'; meals: ScheduleMeals; failed: number }
  | { status: 'ready'; meals: ScheduleMeals; failed: number };

const modes: { value: ScheduleMode; label: string }[] = [
  { value: 'daily', label: '일간' },
  { value: 'weekly', label: '주간' },
  { value: 'monthly', label: '월간' },
];

const demoMenus = [
  ['현미밥', '닭갈비', '브로콜리무침', '깍두기', '우유'],
  ['흑미밥', '미역국', '돼지불고기', '애호박볶음', '배추김치'],
  ['카레라이스', '과일샐러드', '콘샐러드', '단무지', '요구르트'],
  ['보리밥', '된장찌개', '제육볶음', '오이무침', '배추김치'],
  ['볶음밥', '계란국', '두부조림', '시금치무침', '우유'],
] as const;

function parseDateKey(value: string): Date {
  return new Date(Date.UTC(
    Number(value.slice(0, 4)),
    Number(value.slice(4, 6)) - 1,
    Number(value.slice(6, 8)),
  ));
}

function dateKey(value: Date): string {
  return [
    value.getUTCFullYear(),
    String(value.getUTCMonth() + 1).padStart(2, '0'),
    String(value.getUTCDate()).padStart(2, '0'),
  ].join('');
}

function addDays(value: Date, amount: number): Date {
  const next = new Date(value);
  next.setUTCDate(next.getUTCDate() + amount);
  return next;
}

function startOfWeek(value: Date): Date {
  const weekday = value.getUTCDay();
  return addDays(value, weekday === 0 ? -6 : 1 - weekday);
}

function weekDates(value: Date): Date[] {
  const monday = startOfWeek(value);
  return Array.from({ length: 5 }, (_, index) => addDays(monday, index));
}

function monthWeekRows(value: Date): (Date | null)[][] {
  const year = value.getUTCFullYear();
  const month = value.getUTCMonth();
  const first = new Date(Date.UTC(year, month, 1));
  const last = new Date(Date.UTC(year, month + 1, 0));
  const rows: (Date | null)[][] = [];
  let cursor = startOfWeek(first);

  while (cursor <= last || cursor.getUTCMonth() === month) {
    const row = Array.from({ length: 5 }, (_, index) => {
      const date = addDays(cursor, index);
      return date.getUTCMonth() === month ? date : null;
    });
    if (row.some(Boolean)) rows.push(row);
    cursor = addDays(cursor, 7);
    if (cursor > last && cursor.getUTCMonth() !== month) break;
  }
  return rows;
}

function datesFor(mode: ScheduleMode, anchor: Date): Date[] {
  if (mode === 'daily') return [anchor];
  if (mode === 'weekly') return weekDates(anchor);
  return monthWeekRows(anchor).flatMap((row) => row.filter((date): date is Date => date !== null));
}

function shiftAnchor(anchor: Date, mode: ScheduleMode, direction: -1 | 1): Date {
  const next = new Date(anchor);
  if (mode === 'daily') next.setUTCDate(next.getUTCDate() + direction);
  if (mode === 'weekly') next.setUTCDate(next.getUTCDate() + (7 * direction));
  if (mode === 'monthly') next.setUTCMonth(next.getUTCMonth() + direction, 1);
  return next;
}

function weekday(value: Date): string {
  return ['일', '월', '화', '수', '목', '금', '토'][value.getUTCDay()];
}

function fullDateLabel(value: Date): string {
  return `${value.getUTCFullYear()}년 ${value.getUTCMonth() + 1}월 ${value.getUTCDate()}일 (${weekday(value)})`;
}

function periodLabel(mode: ScheduleMode, anchor: Date): string {
  if (mode === 'daily') return fullDateLabel(anchor);
  if (mode === 'monthly') return `${anchor.getUTCFullYear()}년 ${anchor.getUTCMonth() + 1}월`;
  const dates = weekDates(anchor);
  const start = dates[0];
  const end = dates.at(-1) ?? start;
  return `${start.getUTCMonth() + 1}월 ${start.getUTCDate()}일 - ${end.getUTCMonth() + 1}월 ${end.getUTCDate()}일`;
}

function makeDemoMeal(date: Date): MealDay {
  const menu = demoMenus[(date.getUTCDate() - 1) % demoMenus.length];
  const key = dateKey(date);
  return {
    date: key,
    menuItems: menu.map((name, index): MealItem => ({
      id: `${key}-${index}`,
      name,
      allergyCodes: [],
      nutrients: [],
      tags: [],
      sourceRawText: name,
    })),
    calorie: `${570 + ((date.getUTCDate() * 13) % 80)} Kcal`,
    nutrition: null,
    isSample: true,
    notice: '체험용 급식표예요.',
  };
}

function mealCategory(name: string): 'staple' | 'soup' | 'side' | 'kimchi' | 'drink' {
  if (/(밥|라이스|면|국수|스파게티|우동)/.test(name)) return 'staple';
  if (/(국|탕|찌개|전골|스프)/.test(name)) return 'soup';
  if (/(김치|깍두기|단무지)/.test(name)) return 'kimchi';
  if (/(우유|주스|요구르트|요거트|음료)/.test(name)) return 'drink';
  return 'side';
}

const scheduleRows = [
  { key: 'staple', label: '밥/면', emoji: '🍚' },
  { key: 'soup', label: '국/탕', emoji: '🥣' },
  { key: 'side', label: '반찬', emoji: '🥗' },
  { key: 'kimchi', label: '김치', emoji: '🥬' },
  { key: 'drink', label: '음료', emoji: '🥛' },
] as const;

function menuFor(meal: MealDay | null | undefined, category: typeof scheduleRows[number]['key']): string {
  if (!meal) return '—';
  const names = meal.menuItems
    .filter((item) => mealCategory(item.name) === category)
    .map((item) => item.name);
  return names.length > 0 ? names.join(' · ') : '—';
}

function averageCalories(meals: MealDay[]): number | null {
  const values = meals
    .map((meal) => Number.parseFloat(meal.calorie ?? ''))
    .filter(Number.isFinite);
  if (values.length === 0) return null;
  return Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
}

export function MealSchedulePage() {
  const [searchParams] = useSearchParams();
  const demo = searchParams.get('demo') === '1';
  const { state, repository } = useAppState();
  const profile = state.status === 'ready' ? state.profile : null;
  const [mode, setMode] = useState<ScheduleMode>('daily');
  const [anchor, setAnchor] = useState(() => parseDateKey(seoulDate()));
  const visibleDates = useMemo(() => datesFor(mode, anchor), [mode, anchor]);
  const visibleKey = visibleDates.map(dateKey).join(',');
  const [schedule, setSchedule] = useState<ScheduleState>({
    status: 'loading',
    meals: {},
    failed: 0,
  });

  useEffect(() => {
    let active = true;
    const controller = new AbortController();
    const load = async () => {
      setSchedule((current) => ({ ...current, status: 'loading', failed: 0 }));
      if (demo) {
        const meals = Object.fromEntries(
          visibleDates.map((date) => [dateKey(date), makeDemoMeal(date)]),
        );
        if (active) setSchedule({ status: 'ready', meals, failed: 0 });
        return;
      }
      if (profile === null) {
        if (active) setSchedule({ status: 'ready', meals: {}, failed: 1 });
        return;
      }

      const meals: ScheduleMeals = {};
      let failed = 0;
      for (let offset = 0; offset < visibleDates.length; offset += 5) {
        const batch = visibleDates.slice(offset, offset + 5);
        const results = await Promise.all(batch.map(async (date) => {
          const key = dateKey(date);
          try {
            const meal = await neisClient.fetchMeal(profile.school, key, controller.signal);
            try {
              await repository.cacheMeal(profile.school, meal);
            } catch {
              // A successful live meal wins even when optional device caching fails.
            }
            return { key, meal, failed: false };
          } catch (caught) {
            if (controller.signal.aborted) throw caught;
            if (caught instanceof NeisClientError && caught.code === 'NO_DATA') {
              return { key, meal: null, failed: false };
            }
            try {
              const cached = await repository.getCachedMeal(profile.school, key);
              if (cached !== null) return { key, meal: cached.meal, failed: false };
            } catch {
              // Device storage is an optional offline convenience.
            }
            return { key, meal: null, failed: true };
          }
        }));
        for (const result of results) {
          meals[result.key] = result.meal;
          if (result.failed) failed += 1;
        }
      }
      if (active) setSchedule({ status: 'ready', meals, failed });
    };

    void load().catch(() => {
      if (active) setSchedule({ status: 'ready', meals: {}, failed: visibleDates.length });
    });
    return () => {
      active = false;
      controller.abort();
    };
  }, [demo, profile, repository, visibleKey]);

  const loadedMeals = Object.values(schedule.meals).filter((meal): meal is MealDay => meal !== null);
  const calorieAverage = averageCalories(loadedMeals);

  return (
    <ForestScene className="meal-schedule-page" showSettings={!demo}>
      <header className="forest-title-card meal-schedule-title">
        <p className="forest-eyebrow">한눈에 보는 우리 학교 점심</p>
        <h1>급식표</h1>
        <p>일간·주간·월간 메뉴를 미리 확인해요.</p>
      </header>

      <section className="forest-card meal-schedule-controls" aria-label="급식표 보기 설정">
        <div className="meal-schedule-modes">
          {modes.map((item) => (
            <button
              key={item.value}
              type="button"
              aria-pressed={mode === item.value}
              className={mode === item.value ? 'is-selected' : ''}
              onClick={() => setMode(item.value)}
            >
              {item.label}
            </button>
          ))}
        </div>
        <div className="meal-schedule-period">
          <button
            type="button"
            aria-label="이전 기간"
            onClick={() => setAnchor((current) => shiftAnchor(current, mode, -1))}
          >
            ‹
          </button>
          <strong>{periodLabel(mode, anchor)}</strong>
          <button
            type="button"
            aria-label="다음 기간"
            onClick={() => setAnchor((current) => shiftAnchor(current, mode, 1))}
          >
            ›
          </button>
        </div>
        <button
          type="button"
          className="meal-schedule-today"
          onClick={() => setAnchor(parseDateKey(seoulDate()))}
        >
          오늘로
        </button>
      </section>

      {schedule.status === 'loading' ? (
        <section className="forest-card meal-schedule-loading" role="status">
          <strong>급식표를 불러오고 있어요</strong>
          <div className="meal-skeleton" aria-hidden="true"><span /><span /><span /></div>
        </section>
      ) : (
        <>
          {schedule.failed > 0 ? (
            <p className="forest-notice">
              일부 날짜의 급식을 불러오지 못했어요. 저장된 메뉴가 있으면 함께 표시했어요.
            </p>
          ) : null}
          {demo ? <p className="forest-notice">지금은 급식표 체험 화면이에요.</p> : null}

          {mode === 'daily' ? (
            <DailySchedule date={anchor} meal={schedule.meals[dateKey(anchor)]} />
          ) : null}
          {mode === 'weekly' ? (
            <WeeklySchedule dates={weekDates(anchor)} meals={schedule.meals} />
          ) : null}
          {mode === 'monthly' ? (
            <MonthlySchedule anchor={anchor} meals={schedule.meals} />
          ) : null}

          <section className="forest-card meal-schedule-nutrition" aria-label="급식표 영양 요약">
            <div>
              <span>표시된 급식</span>
              <strong>{loadedMeals.length}일</strong>
            </div>
            <div>
              <span>평균 열량</span>
              <strong>{calorieAverage === null ? '정보 없음' : `${calorieAverage} kcal`}</strong>
            </div>
          </section>
        </>
      )}

      <ForestNavigation />
    </ForestScene>
  );
}

function DailySchedule({ date, meal }: { date: Date; meal: MealDay | null | undefined }) {
  return (
    <section className="forest-card meal-schedule-daily" aria-label="일간 급식표">
      <header>
        <div>
          <p className="forest-eyebrow">오늘의 메뉴</p>
          <h2>{fullDateLabel(date)}</h2>
        </div>
        {meal?.calorie ? <span>{meal.calorie}</span> : null}
      </header>
      <div className="meal-schedule-daily__rows">
        {scheduleRows.map((row) => (
          <div key={row.key}>
            <span aria-hidden="true">{row.emoji}</span>
            <strong>{row.label}</strong>
            <p>{menuFor(meal, row.key)}</p>
          </div>
        ))}
      </div>
      {!meal ? <p className="meal-schedule-empty">등록된 급식이 없어요.</p> : null}
    </section>
  );
}

function WeeklySchedule({ dates, meals }: { dates: Date[]; meals: ScheduleMeals }) {
  return (
    <section className="forest-card meal-schedule-table-card" aria-label="주간 급식표">
      <div className="meal-schedule-table-scroll">
        <table>
          <thead>
            <tr>
              <th scope="col">구분</th>
              {dates.map((date) => (
                <th key={dateKey(date)} scope="col">
                  <span>{weekday(date)}</span>
                  <strong>{date.getUTCMonth() + 1}/{date.getUTCDate()}</strong>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {scheduleRows.map((row) => (
              <tr key={row.key}>
                <th scope="row">{row.emoji}<span>{row.label}</span></th>
                {dates.map((date) => (
                  <td key={dateKey(date)}>{menuFor(meals[dateKey(date)], row.key)}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function MonthlySchedule({ anchor, meals }: { anchor: Date; meals: ScheduleMeals }) {
  const rows = monthWeekRows(anchor);
  return (
    <section className="forest-card meal-schedule-monthly" aria-label="월간 급식표">
      <div className="meal-schedule-monthly__weekdays" aria-hidden="true">
        {['월', '화', '수', '목', '금'].map((day) => <strong key={day}>{day}</strong>)}
      </div>
      <div className="meal-schedule-monthly__grid">
        {rows.flatMap((row, rowIndex) => row.map((date, columnIndex) => {
          const key = date ? dateKey(date) : `empty-${rowIndex}-${columnIndex}`;
          const meal = date ? meals[key] : null;
          return (
            <article className={date ? '' : 'is-empty'} key={key}>
              {date ? (
                <>
                  <strong>{date.getUTCDate()}</strong>
                  {meal ? (
                    <ul>
                      {meal.menuItems.slice(0, 4).map((item) => <li key={item.id}>{item.name}</li>)}
                    </ul>
                  ) : <span>—</span>}
                </>
              ) : null}
            </article>
          );
        }))}
      </div>
    </section>
  );
}
