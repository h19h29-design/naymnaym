import { useRef, useState } from 'react';
import type { MealItem } from '@nyam/neis-contract';
import { useSearchParams } from 'react-router-dom';
import { AppErrorState } from '../../components/AppErrorState';
import { GrowthHeader } from '../../components/GrowthHeader';
import { MealCard } from '../../components/MealCard';
import { allergyRisk } from '../../domain/allergy';
import { calculateXp, hasPreviousDayRecord } from '../../domain/progress';
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
import { useTodayMeal } from './useTodayMeal';

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
      // Retrying writes this same complete snapshot, so partially completed device
      // writes cannot add XP a second time or create a different challenge record.
      await repository.saveRecords(pending.records);
      await repository.saveProgress(pending.progress);
      await repository.saveChallengeRecords(pending.challengeRecords);
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

  if (result === 'loading') {
    return <main className="app-shell">
      {sessionMode.kind === 'live' && <h1>오늘 급식</h1>}
      불러오는 중...
    </main>;
  }
  if (result.kind === 'noMeal') {
    return <main className="app-shell"><h1>오늘 급식</h1><p>오늘은 등록된 급식이 없어요</p></main>;
  }
  if (result.kind === 'error') {
    return <main className="app-shell"><h1>오늘 급식</h1><AppErrorState code={result.code} retry={retry} /></main>;
  }

  const sourceLabel = {
    live: '오늘 급식',
    cache: '저장된 급식 정보예요',
    demo: '체험 급식',
  }[result.kind];
  const disabled = isSaving || hasPendingSave;

  return (
    <main className="app-shell">
      <GrowthHeader totalXp={progress.totalXp} />
      <h1>오늘 급식</h1>
      {result.kind !== 'live' && <p>{sourceLabel}</p>}
      {result.kind === 'demo' && <p>체험 기록은 저장되지 않아요</p>}
      {demoNotice && <p role="status">{demoNotice}</p>}
      {saveError && (
        <section role="alert">
          <p>{saveError}</p>
          <button type="button" onClick={retrySave} disabled={isSaving}>다시 시도</button>
        </section>
      )}
      {result.meal.menuItems.map((item) => (
        <MealCard
          key={item.id}
          item={item}
          allergyCodes={profile?.allergyCodes ?? []}
          disabled={disabled}
          onRecord={(status, reason) => { void record(item, status, reason); }}
        />
      ))}
    </main>
  );
}
