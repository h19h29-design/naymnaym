import { useEffect, useMemo, useState } from 'react';
import type { MealDay } from '@nyam/neis-contract';
import type { Profile, SessionMode } from '../../domain/types';
import { NeisClientError, type NeisClient } from '../../services/neisClient';
import { isValidLiveMeal, type AppRepository } from '../../services/repository';
import { demoMeal } from './demoMeal';

export type TodayMealResult =
  | { kind: 'live'; meal: MealDay }
  | { kind: 'cache'; meal: MealDay }
  | { kind: 'demo'; meal: MealDay }
  | { kind: 'noMeal' }
  | { kind: 'error'; code: string };

export function seoulDate(now = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value;
  return `${get('year')}${get('month')}${get('day')}`;
}

export function millisecondsUntilNextSeoulMidnight(now = new Date()): number {
  const current = seoulDate(now);
  const year = Number(current.slice(0, 4));
  const month = Number(current.slice(4, 6));
  const day = Number(current.slice(6, 8));
  const nextMidnight = Date.UTC(year, month - 1, day + 1) - (9 * 60 * 60 * 1000);
  return Math.max(1, nextMidnight - now.getTime());
}

export async function loadTodayMeal(input: {
  mode: SessionMode;
  profile: Profile | null;
  client: NeisClient;
  repository: AppRepository;
  now?: Date;
}): Promise<TodayMealResult> {
  if (input.mode.kind === 'demo') return { kind: 'demo', meal: demoMeal };
  if (input.profile === null) return { kind: 'error', code: 'PROFILE_REQUIRED' };

  const date = seoulDate(input.now);
  try {
    const meal = await input.client.fetchMeal(input.profile.school, date);
    if (!isValidLiveMeal(meal, date)) {
      throw new NeisClientError('UPSTREAM_ERROR', '급식 정보를 불러오지 못했어요.', 502);
    }
    try {
      await input.repository.cacheMeal(input.profile.school, meal);
    } catch {
      // A device cache is only an offline convenience; a successful live result wins.
    }
    return { kind: 'live', meal };
  } catch (caught) {
    if (caught instanceof NeisClientError && caught.code === 'NO_DATA') {
      return { kind: 'noMeal' };
    }
    try {
      const cached = await input.repository.getCachedMeal(input.profile.school, date);
      if (cached !== null && isValidLiveMeal(cached.meal, date)) {
        return { kind: 'cache', meal: cached.meal };
      }
    } catch {
      // Treat unavailable device storage as a normal recoverable load failure.
    }
    return {
      kind: 'error',
      code: caught instanceof NeisClientError ? caught.code : 'UPSTREAM_ERROR',
    };
  }
}

export function useTodayMeal(input: Omit<Parameters<typeof loadTodayMeal>[0], 'now'>) {
  const [result, setResult] = useState<'loading' | TodayMealResult>('loading');
  const [attempt, setAttempt] = useState(0);
  const [date, setDate] = useState(() => seoulDate());
  const profileKey = input.profile === null
    ? null
    : `${input.profile.school.officeCode}:${input.profile.school.schoolCode}`;
  const stableInput = useMemo(() => input, [
    input.mode.kind,
    profileKey,
    input.client,
    input.repository,
  ]);

  useEffect(() => {
    let active = true;
    setResult('loading');
    void loadTodayMeal(stableInput)
      .then((next) => {
        if (active) setResult(next);
      })
      .catch(() => {
        if (active) setResult({ kind: 'error', code: 'UPSTREAM_ERROR' });
      });
    return () => { active = false; };
  }, [stableInput, date, attempt]);

  useEffect(() => {
    let timer: number | undefined;
    const refreshDate = () => {
      setDate((current) => {
        const next = seoulDate();
        return current === next ? current : next;
      });
    };
    const scheduleMidnight = () => {
      timer = window.setTimeout(() => {
        refreshDate();
        scheduleMidnight();
      }, millisecondsUntilNextSeoulMidnight());
    };
    const onVisibilityChange = () => {
      if (document.visibilityState === 'visible') refreshDate();
    };

    scheduleMidnight();
    window.addEventListener('focus', refreshDate);
    document.addEventListener('visibilitychange', onVisibilityChange);
    return () => {
      if (timer !== undefined) window.clearTimeout(timer);
      window.removeEventListener('focus', refreshDate);
      document.removeEventListener('visibilitychange', onVisibilityChange);
    };
  }, []);

  return { result, retry: () => setAttempt((value) => value + 1) };
}
