import { useEffect, useMemo, useState } from 'react';
import type { MealDay } from '@nyam/neis-contract';
import type { Profile } from '../../domain/types';
import { NeisClientError, type NeisClient } from '../../services/neisClient';
import { isValidLiveMeal, type AppRepository } from '../../services/repository';
import { seoulDate } from './useTodayMeal';

export type NextMealResult =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'live'; meal: MealDay }
  | { kind: 'cache'; meal: MealDay }
  | { kind: 'notFound' }
  | { kind: 'error'; code: string };

function parseDateKey(date: string): Date {
  return new Date(Date.UTC(
    Number(date.slice(0, 4)),
    Number(date.slice(4, 6)) - 1,
    Number(date.slice(6, 8)),
  ));
}

function addDays(date: Date, days: number): Date {
  return new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate() + days,
  ));
}

function dateKey(date: Date): string {
  return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, '0')}${String(date.getUTCDate()).padStart(2, '0')}`;
}

function isAbort(caught: unknown, signal?: AbortSignal): boolean {
  return signal?.aborted === true || (caught instanceof DOMException && caught.name === 'AbortError');
}

export function nextMealCandidateDates(now = new Date()): string[] {
  const start = parseDateKey(seoulDate(now));
  return Array.from({ length: 7 }, (_, offset) => addDays(start, offset + 1))
    .filter((date) => date.getUTCDay() !== 0 && date.getUTCDay() !== 6)
    .map(dateKey);
}

export async function loadNextMeal(input: {
  profile: Profile | null;
  client: NeisClient;
  repository: AppRepository;
  now?: Date;
  signal?: AbortSignal;
  mutationEpoch?: number;
}): Promise<NextMealResult> {
  if (input.profile === null) return { kind: 'error', code: 'PROFILE_REQUIRED' };

  for (const date of nextMealCandidateDates(input.now)) {
    try {
      const meal = await input.client.fetchMeal(input.profile.school, date, input.signal);
      if (input.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
      if (!isValidLiveMeal(meal, date)) {
        throw new NeisClientError('UPSTREAM_ERROR', '급식 정보를 불러오지 못했어요.', 502);
      }
      try {
        void input.repository.cacheMeal(input.profile.school, meal, input.mutationEpoch).catch(() => {
          // A device cache is only an offline convenience; a successful live result wins.
        });
      } catch {
        // A device cache is only an offline convenience; a successful live result wins.
      }
      return { kind: 'live', meal };
    } catch (caught) {
      if (isAbort(caught, input.signal)) throw caught;
      if (caught instanceof NeisClientError && caught.code === 'NO_DATA') continue;

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

  return { kind: 'notFound' };
}

export function useNextMeal(input: Omit<Parameters<typeof loadNextMeal>[0], 'now' | 'signal' | 'mutationEpoch'> & {
  active: boolean;
}) {
  const { active } = input;
  const [result, setResult] = useState<NextMealResult>(() => active ? { kind: 'loading' } : { kind: 'idle' });
  const [attempt, setAttempt] = useState(0);
  const profileKey = input.profile === null
    ? null
    : `${input.profile.school.officeCode}:${input.profile.school.schoolCode}`;
  const stableInput = useMemo(() => ({ ...input, active }), [
    active,
    profileKey,
    input.client,
    input.repository,
  ]);

  useEffect(() => {
    if (!stableInput.active) {
      setResult({ kind: 'idle' });
      return undefined;
    }

    let mounted = true;
    const controller = new AbortController();
    const mutationEpoch = typeof stableInput.repository.captureMutationEpoch === 'function'
      ? stableInput.repository.captureMutationEpoch()
      : undefined;
    setResult({ kind: 'loading' });
    void loadNextMeal({ ...stableInput, signal: controller.signal, mutationEpoch })
      .then((next) => {
        if (mounted) setResult(next);
      })
      .catch(() => {
        if (mounted) setResult({ kind: 'error', code: 'UPSTREAM_ERROR' });
      });

    return () => {
      mounted = false;
      controller.abort();
    };
  }, [stableInput, attempt]);

  return { result, retry: () => setAttempt((value) => value + 1) };
}
