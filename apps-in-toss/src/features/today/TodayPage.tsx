import { useRef, useState } from 'react';
import { Button } from '@toss/tds-mobile';
import type { MealItem } from '@nyam/neis-contract';
import { useSearchParams } from 'react-router-dom';
import { AppErrorState } from '../../components/AppErrorState';
import { ForestNavigation } from '../../components/ForestNavigation';
import { ForestScene } from '../../components/ForestScene';
import { MealCard } from '../../components/MealCard';
import { allergyRisk } from '../../domain/allergy';
import { calculateXp, hasPreviousDayRecord, levelFor } from '../../domain/progress';
import { upsertMealRecord } from '../../domain/records';
import type {
  ChallengeRecord,
  DifficultyReason,
  EatingStatus,
  MealRecord,
  Progress,
  SessionMode,
} from '../../domain/types';
import { neisClient } from '../../services/neisClient';
import { useAppState } from '../../state/AppStateProvider';
import { seoulDate, useTodayMeal } from './useTodayMeal';

const DEFAULT_PROGRESS: Progress = {
  totalXp: 0,
  baseEarnedByDate: {},
  challengeEarnedByDate: {},
};

interface PendingSave {
  records: MealRecord[];
  progress: Progress;
  challengeRecords: ChallengeRecord[];
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

export function TodayPage() {
  const [searchParams] = useSearchParams();
  const sessionMode: SessionMode = searchParams.get('demo') === '1'
    ? { kind: 'demo' }
    : { kind: 'live' };
  const { state, repository, reload } = useAppState();
  const profile = state.status === 'ready' ? state.profile : null;
  const persistentProgress = state.status === 'ready' ? state.progress : DEFAULT_PROGRESS;
  const persistentRecords = state.status === 'ready' ? state.mealRecords : [];
  const persistentChallenges = state.status === 'ready' ? state.challengeRecords : [];
  const [demoRecords, setDemoRecords] = useState<MealRecord[]>([]);
  const [demoProgress, setDemoProgress] = useState<Progress>(DEFAULT_PROGRESS);
  const [demoNotice, setDemoNotice] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [hasPendingSave, setHasPendingSave] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [recordingOpen, setRecordingOpen] = useState(false);
  const savingRef = useRef(false);
  const pendingRef = useRef<PendingSave | null>(null);
  const records = sessionMode.kind === 'demo' ? demoRecords : persistentRecords;
  const progress = sessionMode.kind === 'demo' ? demoProgress : persistentProgress;
  const { result, retry } = useTodayMeal({
    mode: sessionMode,
    profile,
    client: neisClient,
    repository,
  });

  const persist = async (pending: PendingSave) => {
    if (savingRef.current) return;
    savingRef.current = true;
    setIsSaving(true);
    setSaveError(null);
    try {
      // The repository journals this exact aggregate in the existing progress
      // value before touching the companion record values. Retrying is idempotent.
      await repository.saveMealFeedbackSnapshot(
        pending.records,
        pending.progress,
        pending.challengeRecords,
      );
      if (!await reload()) throw new Error('reload failed');
      pendingRef.current = null;
      setHasPendingSave(false);
    } catch {
      setSaveError('기록을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      savingRef.current = false;
      setIsSaving(false);
    }
  };

  const retrySave = () => {
    const pending = pendingRef.current;
    if (pending !== null) void persist(pending);
  };

  const record = async (
    item: MealItem,
    status: EatingStatus,
    difficultyReason: DifficultyReason | null = null,
  ) => {
    if (savingRef.current || pendingRef.current !== null) return;
    if (status === 'oneBite' && allergyRisk(item, profile?.allergyCodes ?? []).length > 0) return;

    const meal = result === 'loading' || result.kind === 'noMeal' || result.kind === 'error'
      ? null
      : result.meal;
    if (meal === null) return;
    const previous = records
      .filter((candidate) => candidate.mealName === item.name && candidate.date < meal.date)
      .sort((left, right) => left.date.localeCompare(right.date))
      .at(-1);
    const variedFoodGroup = item.nutrients.length >= 2;
    const streakRecord = hasPreviousDayRecord(records, meal.date);
    const allergySafetyCheck = status === 'allergyAvoided';
    const retry = previous?.status === 'difficultToday';
    const award = calculateXp({
      status,
      previousStatus: previous?.status ?? null,
      baseEarnedToday: progress.baseEarnedByDate[meal.date] ?? 0,
      challengeEarnedToday: progress.challengeEarnedByDate[meal.date] ?? 0,
      variedFoodGroup,
      streakRecord,
      allergySafetyCheck,
    });
    const next: MealRecord = {
      date: meal.date,
      mealItemId: item.id,
      mealName: item.name,
      status,
      difficultyReason,
      awardedXp: award.total,
      recordedAt: new Date().toISOString(),
    };
    const updated = upsertMealRecord(records, next);
    const earnedBase = updated.newXp > 0 ? award.base : 0;
    const earnedChallenge = updated.newXp > 0 ? award.challenge : 0;
    const nextProgress: Progress = {
      totalXp: progress.totalXp + updated.newXp,
      baseEarnedByDate: {
        ...progress.baseEarnedByDate,
        [meal.date]: (progress.baseEarnedByDate[meal.date] ?? 0) + earnedBase,
      },
      challengeEarnedByDate: {
        ...progress.challengeEarnedByDate,
        [meal.date]: (progress.challengeEarnedByDate[meal.date] ?? 0) + earnedChallenge,
      },
    };
    const nextChallenges = earnedChallenge > 0
      ? [...persistentChallenges, {
        date: meal.date,
        mealItemId: item.id,
        kinds: [
          ...(variedFoodGroup ? ['variedFoodGroup' as const] : []),
          ...(streakRecord ? ['streakRecord' as const] : []),
          ...(allergySafetyCheck ? ['allergySafetyCheck' as const] : []),
          ...(retry ? ['retry' as const] : []),
        ],
        awardedXp: earnedChallenge,
      }]
      : persistentChallenges;

    if (sessionMode.kind === 'demo') {
      setDemoRecords(updated.records);
      setDemoProgress(nextProgress);
      setDemoNotice('체험 기록을 남겼어요. 이 기록은 저장되지 않아요.');
      return;
    }

    const pending = {
      records: updated.records,
      progress: nextProgress,
      challengeRecords: nextChallenges,
    };
    pendingRef.current = pending;
    setHasPendingSave(true);
    await persist(pending);
  };

  const meal = result === 'loading' || result.kind === 'noMeal' || result.kind === 'error'
    ? null
    : result.meal;
  const sourceLabel = result === 'loading'
    ? '급식을 확인하고 있어요'
    : {
      live: '오늘 급식',
      cache: '저장된 급식',
      demo: '체험 급식',
      noMeal: '등록된 급식 없음',
      error: '불러오지 못함',
    }[result.kind];
  const disabled = isSaving || hasPendingSave;
  const level = levelFor(progress.totalXp);
  const dateText = formattedKoreanDate(meal?.date ?? seoulDate());
  const characterMessage = result === 'loading'
    ? '오늘 급식을 준비하고 있어요.'
    : result.kind === 'noMeal'
    ? '오늘은 쉬어 가는 날이에요.'
    : result.kind === 'error'
    ? '잠시 후 다시 만나 볼까요?'
    : result.kind === 'cache'
    ? '인터넷이 없어도 저장된 급식을 기록할 수 있어요.'
    : result.kind === 'demo'
    ? '체험 모드에서 먼저 만나 볼까요?'
    : '오늘 급식도 함께 만나 볼까요?';

  return (
    <ForestScene className="today-page" showSettings={sessionMode.kind === 'live'}>
      <header className="forest-title-card">
        <h1>오늘 급식</h1>
        <p>{dateText}</p>
      </header>

      <section className="character-stage" aria-label="성장 캐릭터">
        <img
          src={`/growth/level-${level.number}.png`}
          alt={`레벨 ${level.number} ${level.title} 캐릭터`}
        />
        <strong>{characterMessage}</strong>
      </section>

      <section className="forest-card meal-summary" aria-label="오늘의 점심">
        <div className="meal-summary__heading">
          <div>
            <h2>오늘의 점심</h2>
            <p>{sourceLabel}</p>
          </div>
          {meal?.calorie ? <span>{meal.calorie}</span> : null}
        </div>

        {result === 'loading' ? (
          <div className="meal-skeleton" role="status" aria-label="급식을 불러오는 중">
            <span />
            <span />
            <span />
          </div>
        ) : result.kind === 'error' ? (
          <AppErrorState code={result.code} retry={retry} />
        ) : result.kind === 'noMeal' ? (
          <p className="meal-summary__message">오늘은 등록된 급식이 없어요.</p>
        ) : (
          <ul className="meal-summary__list">
            {result.meal.menuItems.map((item) => {
              const risky = allergyRisk(item, profile?.allergyCodes ?? []).length > 0;
              return (
                <li className={risky ? 'is-risk' : ''} key={item.id}>
                  <span aria-hidden="true" />
                  <span>{item.name}</span>
                  {risky ? <em>주의</em> : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {result !== 'loading' && result.kind === 'demo' ? (
        <p className="forest-notice">체험 기록은 저장되지 않아요.</p>
      ) : null}
      {demoNotice ? <p className="forest-notice" role="status">{demoNotice}</p> : null}
      {saveError && !recordingOpen ? (
        <section className="forest-alert" role="alert">
          <p>{saveError}</p>
          <button type="button" onClick={retrySave} disabled={isSaving}>다시 시도</button>
        </section>
      ) : null}

      <button
        className="forest-primary-action"
        type="button"
        disabled={meal === null || disabled}
        onClick={() => setRecordingOpen(true)}
      >
        {meal === null ? '오늘은 기록할 급식이 없어요' : '오늘 급식 기록하기'}
      </button>

      <section className="forest-card growth-summary" aria-label="현재 성장">
        <span className="growth-summary__spark" aria-hidden="true">✦</span>
        <div>
          <p>현재 성장</p>
          <strong>레벨 {level.number} · {level.title} · 총 {progress.totalXp} XP</strong>
        </div>
      </section>

      <ForestNavigation />

      {recordingOpen ? (
        <div
          className="recording-overlay"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setRecordingOpen(false);
          }}
        >
          <section
            className="recording-sheet-surface"
            role="dialog"
            aria-modal="true"
            aria-label="급식 기록"
          >
            <div className="recording-sheet">
            <header>
              <div>
                <p className="forest-eyebrow">메뉴별로 오늘의 경험을 남겨요</p>
                <h2>급식 기록</h2>
              </div>
              <Button color="light" onClick={() => setRecordingOpen(false)}>닫기</Button>
            </header>
            {saveError ? (
              <section className="forest-alert" role="alert">
                <p>{saveError}</p>
                <button type="button" onClick={retrySave} disabled={isSaving}>다시 시도</button>
              </section>
            ) : null}
            {meal?.menuItems.map((item) => (
              <MealCard
                key={item.id}
                item={item}
                allergyCodes={profile?.allergyCodes ?? []}
                disabled={disabled}
                onRecord={(status, reason) => { void record(item, status, reason); }}
              />
            ))}
          </div>
          </section>
        </div>
      ) : null}
    </ForestScene>
  );
}
