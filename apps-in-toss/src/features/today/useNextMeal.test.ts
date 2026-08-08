import { render, screen, waitFor } from '@testing-library/react';
import { createElement } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { meal, makeProfile } from '../../test/fixtures';
import { NeisClientError } from '../../services/neisClient';
import { loadNextMeal, nextMealCandidateDates, useNextMeal } from './useNextMeal';

afterEach(() => {
  vi.restoreAllMocks();
});

describe('next meal loading', () => {
  it('skips weekend dates and searches the closest weekday first', () => {
    expect(nextMealCandidateDates(new Date('2026-08-07T15:00:00.000Z')))
      .toEqual(['20260810', '20260811', '20260812', '20260813', '20260814']);
  });

  it('continues after NO_DATA and stops after the first valid meal', async () => {
    const fetchMeal = vi.fn()
      .mockRejectedValueOnce(new NeisClientError('NO_DATA', '없음', 404))
      .mockResolvedValueOnce({ ...meal, date: '20260811' });

    const result = await loadNextMeal({
      profile: makeProfile(),
      client: { fetchMeal } as never,
      repository: { cacheMeal: vi.fn() } as never,
      now: new Date('2026-08-08T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'live', meal: { ...meal, date: '20260811' } });
    expect(fetchMeal).toHaveBeenCalledTimes(2);
  });

  it('loads by default and makes no request only while inactive', async () => {
    const fetchMeal = vi.fn().mockResolvedValue({ ...meal, date: '20260810' });
    const repository = { cacheMeal: vi.fn().mockResolvedValue(undefined) };
    const profile = makeProfile();
    const client = { fetchMeal } as never;

    function Probe({ active }: { active?: boolean }) {
      const { result } = useNextMeal({
        active,
        profile,
        client,
        repository: repository as never,
      });
      return createElement('output', undefined, result.kind);
    }

    const view = render(createElement(Probe, { active: false }));
    expect(screen.getByText('idle')).toBeInTheDocument();
    expect(fetchMeal).not.toHaveBeenCalled();

    view.rerender(createElement(Probe));
    await waitFor(() => expect(screen.getByText('live')).toBeInTheDocument());
    expect(fetchMeal).toHaveBeenCalledTimes(1);
  });

  it('returns notFound after all five candidate weekdays report NO_DATA', async () => {
    const fetchMeal = vi.fn().mockRejectedValue(new NeisClientError('NO_DATA', '없음', 404));
    const result = await loadNextMeal({
      profile: makeProfile(),
      client: { fetchMeal } as never,
      repository: { getCachedMeal: vi.fn() } as never,
      now: new Date('2026-08-08T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'notFound' });
    expect(fetchMeal).toHaveBeenCalledTimes(5);
  });

  it('uses only an exact-date cache after an upstream failure', async () => {
    const cachedMeal = { ...meal, date: '20260810' };
    const cacheMeal = vi.fn();
    const result = await loadNextMeal({
      profile: makeProfile(),
      client: {
        fetchMeal: vi.fn().mockRejectedValue(new NeisClientError('UPSTREAM_ERROR', '다운', 503)),
      } as never,
      repository: {
        cacheMeal,
        getCachedMeal: vi.fn().mockResolvedValue({ meal: cachedMeal, source: 'cache' }),
      } as never,
      now: new Date('2026-08-08T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'cache', meal: cachedMeal });
    expect(cacheMeal).not.toHaveBeenCalled();
  });

  it('rejects a cache entry for a different date after an upstream failure', async () => {
    const result = await loadNextMeal({
      profile: makeProfile(),
      client: {
        fetchMeal: vi.fn().mockRejectedValue(new NeisClientError('UPSTREAM_ERROR', '다운', 503)),
      } as never,
      repository: {
        getCachedMeal: vi.fn().mockResolvedValue({
          meal: { ...meal, date: '20260811' },
          source: 'cache',
        }),
      } as never,
      now: new Date('2026-08-08T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'error', code: 'UPSTREAM_ERROR' });
  });

  it('keeps a valid live meal when device cache writing fails', async () => {
    const liveMeal = { ...meal, date: '20260810' };
    const result = await loadNextMeal({
      profile: makeProfile(),
      client: { fetchMeal: vi.fn().mockResolvedValue(liveMeal) } as never,
      repository: { cacheMeal: vi.fn().mockRejectedValue(new Error('storage unavailable')) } as never,
      now: new Date('2026-08-08T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'live', meal: liveMeal });
  });

  it('aborts its owned request when deactivated', async () => {
    let signal: AbortSignal | undefined;
    const fetchMeal = vi.fn((_school, _date, requestSignal?: AbortSignal) => {
      signal = requestSignal;
      return new Promise<never>(() => undefined);
    });
    const profile = makeProfile();
    const client = { fetchMeal } as never;
    const repository = { cacheMeal: vi.fn() } as never;

    function Probe({ active }: { active: boolean }) {
      const { result } = useNextMeal({ active, profile, client, repository });
      return createElement('output', undefined, result.kind);
    }

    const view = render(createElement(Probe, { active: true }));
    await waitFor(() => expect(fetchMeal).toHaveBeenCalledTimes(1));
    view.rerender(createElement(Probe, { active: false }));

    expect(signal?.aborted).toBe(true);
    expect(screen.getByText('idle')).toBeInTheDocument();
  });
});
