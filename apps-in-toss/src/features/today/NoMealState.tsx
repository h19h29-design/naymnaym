import type { MealDay } from '@nyam/neis-contract';
import type { ReactNode } from 'react';
import { ALLERGIES, allergyRisk } from '../../domain/allergy';
import { levelFor } from '../../domain/progress';
import type { NextMealResult } from './useNextMeal';

type Level = ReturnType<typeof levelFor>;

interface Props {
  level: Level;
  totalXp: number;
  allergyCodes: number[];
  nextMeal: NextMealResult;
  onRetryToday: () => void;
  onRetryNext: () => void;
  onOpenWeekly: () => void;
  onEditSchool: () => void;
}

function formattedKoreanDate(value: string): string {
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(4, 6));
  const day = Number(value.slice(6, 8));
  const weekday = ['일', '월', '화', '수', '목', '금', '토'][
    new Date(Date.UTC(year, month - 1, day)).getUTCDay()
  ];
  return `${month}월 ${day}일 ${weekday}요일`;
}

function allergyNames(meal: MealDay, allergyCodes: number[]): string[] {
  return [...new Set(meal.menuItems.flatMap((item) => allergyRisk(item, allergyCodes)))]
    .map((code) => ALLERGIES[code as keyof typeof ALLERGIES])
    .filter((name) => name !== undefined);
}

function MealDetails({ meal, source, allergyCodes }: {
  meal: MealDay;
  source: 'live' | 'cache';
  allergyCodes: number[];
}) {
  const risks = allergyNames(meal, allergyCodes);

  return (
    <div className="no-meal-recovery__next-content" role="status">
      <p className="no-meal-recovery__source">
        {source === 'cache' ? '저장된 다음 급식' : '다음 급식 정보'}
      </p>
      <div className="no-meal-recovery__meal-meta">
        <strong>{formattedKoreanDate(meal.date)}</strong>
        {meal.calorie ? <span>{meal.calorie}</span> : null}
      </div>
      <ul className="no-meal-recovery__menu">
        {meal.menuItems.map((item) => {
          const risky = allergyRisk(item, allergyCodes).length > 0;
          return (
            <li className={risky ? 'is-risk' : ''} key={item.id}>
              <span>{item.name}</span>
              {risky ? <em>주의</em> : null}
            </li>
          );
        })}
      </ul>
      <p className={risks.length > 0 ? 'no-meal-recovery__allergy is-risk' : 'no-meal-recovery__allergy'}>
        {risks.length > 0
          ? `알레르기 안전을 먼저 확인해 주세요 · ${risks.join(', ')}`
          : '알레르기 표시를 먼저 확인해 주세요'}
      </p>
    </div>
  );
}

function NextMealPreview({ result, allergyCodes, onRetry }: {
  result: NextMealResult;
  allergyCodes: number[];
  onRetry: () => void;
}) {
  let content: ReactNode;

  switch (result.kind) {
    case 'idle':
    case 'loading':
      content = <p role="status">다음 급식을 확인하고 있어요</p>;
      break;
    case 'live':
    case 'cache':
      content = <MealDetails meal={result.meal} source={result.kind} allergyCodes={allergyCodes} />;
      break;
    case 'notFound':
      content = <p role="status">다음 급식을 찾지 못했어요</p>;
      break;
    case 'error':
      content = (
        <div role="alert">
          <p>다음 급식을 불러오지 못했어요</p>
          <button type="button" onClick={onRetry}>다음 급식 다시 시도</button>
        </div>
      );
      break;
  }

  return (
    <section className="no-meal-recovery__next" aria-label="다음 급식">
      <h3>다음 급식</h3>
      {content}
    </section>
  );
}

export function NoMealState({
  level,
  totalXp,
  allergyCodes,
  nextMeal,
  onRetryToday,
  onRetryNext,
  onOpenWeekly,
  onEditSchool,
}: Props) {
  return (
    <section className="forest-card no-meal-recovery" aria-label="급식 없음 안내">
      <img
        src={`/growth/level-${level.number}.png`}
        alt={`레벨 ${level.number} ${level.title} 캐릭터`}
      />
      <p className="forest-eyebrow">레벨 {level.number} · 총 {totalXp} XP</p>
      <h2>오늘은 급식이 없는 날이에요</h2>
      <p>다람쥐도 잠깐 쉬어가요!</p>
      <NextMealPreview result={nextMeal} allergyCodes={allergyCodes} onRetry={onRetryNext} />
      <div className="no-meal-recovery__actions">
        <button type="button" onClick={onOpenWeekly}>주간 급식표 보기</button>
        <button type="button" onClick={onRetryToday}>다시 확인</button>
      </div>
      {nextMeal.kind === 'notFound' ? (
        <button className="no-meal-recovery__school" type="button" onClick={onEditSchool}>
          학교 설정 확인
        </button>
      ) : null}
    </section>
  );
}
