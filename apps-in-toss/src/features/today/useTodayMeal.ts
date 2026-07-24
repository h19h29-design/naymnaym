import { useEffect, useMemo, useState } from 'react';
import type { MealDay } from '@nyam/neis-contract';
import type { Profile, SessionMode } from '../../domain/types';
import { NeisClientError, type NeisClient } from '../../services/neisClient';
import type { AppRepository } from '../../services/repository';
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
      if (cached !== null && cached.meal.date === date && !cached.meal.isSample) {
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
  const date = seoulDate();
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

  return { result, retry: () => setAttempt((value) => value + 1) };
}
