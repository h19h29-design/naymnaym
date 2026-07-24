import { beforeEach, describe, expect, it } from 'vitest';
import { meal, makeProfile, makeRecord, school } from '../test/fixtures';
import { AppRepository } from './repository';
import type { KeyValueStorage } from './storage';

class MemoryStorage implements KeyValueStorage {
  constructor(private values = new Map<string, string>()) {}

  async getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  async setItem(key: string, value: string) {
    this.values.set(key, value);
  }

  async removeItem(key: string) {
    this.values.delete(key);
  }

  keys() {
    return [...this.values.keys()];
  }
}

function seedAllKeys() {
  return new Map([
    ['nyam-toss:profile:v1', '{}'],
    ['nyam-toss:progress:v1', '{}'],
    ['nyam-toss:meal-records:v1', '[]'],
    ['nyam-toss:challenge-records:v1', '[]'],
    ['nyam-toss:meal-cache:v1', '[]'],
  ]);
}

function cacheEntry(
  cachedMeal = meal,
  key = `${school.officeCode}:${school.schoolCode}:${cachedMeal.date}`,
) {
  return {
    key,
    meal: cachedMeal,
    savedAt: '2026-07-24T03:00:00.000Z',
  };
}

describe('AppRepository', () => {
  let repository: AppRepository;

  beforeEach(() => {
    repository = new AppRepository(new MemoryStorage());
  });

  it('round-trips a profile through the storage adapter', async () => {
    const storage = new MemoryStorage();
    const repository = new AppRepository(storage);

    await repository.saveProfile(makeProfile());

    expect((await repository.load()).profile?.nickname).toBe('냠냠이');
  });

  it('drops only a corrupt value and preserves other keys', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:profile:v1', '{broken'],
      ['nyam-toss:progress:v1', JSON.stringify({ totalXp: 80 })],
    ]));

    const state = await new AppRepository(storage).load();

    expect(state.profile).toBeNull();
    expect(state.progress.totalXp).toBe(80);
  });

  it('drops valid-JSON invalid profile, progress, and meal records independently', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:profile:v1', JSON.stringify({ nickname: 42 })],
      ['nyam-toss:progress:v1', JSON.stringify({ totalXp: '80' })],
      ['nyam-toss:meal-records:v1', JSON.stringify([{ date: 42 }])],
      ['nyam-toss:challenge-records:v1', JSON.stringify([{
        date: '20260724',
        mealItemId: 'meal-1',
        kinds: ['retry'],
        awardedXp: 8,
      }])],
    ]));

    const state = await new AppRepository(storage).load();

    expect(state.profile).toBeNull();
    expect(state.progress.totalXp).toBe(0);
    expect(state.mealRecords).toEqual([]);
    expect(state.challengeRecords).toHaveLength(1);
    expect(storage.keys()).toEqual(['nyam-toss:challenge-records:v1']);
  });

  it('drops valid-JSON invalid challenge records while preserving a profile', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:profile:v1', JSON.stringify(makeProfile())],
      ['nyam-toss:challenge-records:v1', JSON.stringify([{}])],
    ]));

    const state = await new AppRepository(storage).load();

    expect(state.profile?.nickname).toBe('냠냠이');
    expect(state.challengeRecords).toEqual([]);
    expect(storage.keys()).toEqual(['nyam-toss:profile:v1']);
  });

  it('uses fresh nested default progress maps for each load', async () => {
    const first = await repository.load();
    first.progress.baseEarnedByDate['20260724'] = 18;
    first.progress.challengeEarnedByDate['20260724'] = 12;

    const second = await repository.load();

    expect(second.progress).toEqual({
      totalXp: 0,
      baseEarnedByDate: {},
      challengeEarnedByDate: {},
    });
    expect(second.progress.baseEarnedByDate).not.toBe(first.progress.baseEarnedByDate);
    expect(second.progress.challengeEarnedByDate)
      .not.toBe(first.progress.challengeEarnedByDate);
  });

  it('clears every nyam key when the user deletes local data', async () => {
    const storage = new MemoryStorage(seedAllKeys());

    await new AppRepository(storage).deleteAll();

    expect(storage.keys()).toEqual([]);
  });

  it('returns a same-school same-date cached meal as cache data', async () => {
    await repository.cacheMeal(school, meal);

    expect(await repository.getCachedMeal(school, meal.date))
      .toEqual({ meal, source: 'cache' });
  });

  it('returns no cache entry for a school and date that never succeeded', async () => {
    expect(await repository.getCachedMeal(school, '20260724')).toBeNull();
  });

  it('drops a valid-JSON malformed meal cache without affecting progress', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:meal-cache:v1', '{}'],
      ['nyam-toss:progress:v1', JSON.stringify({ totalXp: 80 })],
    ]));
    const repository = new AppRepository(storage);

    expect(await repository.getCachedMeal(school, meal.date)).toBeNull();
    expect((await repository.load()).progress.totalXp).toBe(80);
    expect(storage.keys()).toEqual(['nyam-toss:progress:v1']);
  });

  it('drops a cache entry whose key date differs from its meal date', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:meal-cache:v1', JSON.stringify([
        cacheEntry(
          { ...meal, date: '20260725' },
          `${school.officeCode}:${school.schoolCode}:${meal.date}`,
        ),
      ])],
      ['nyam-toss:profile:v1', JSON.stringify(makeProfile())],
    ]));
    const repository = new AppRepository(storage);

    expect(await repository.getCachedMeal(school, meal.date)).toBeNull();
    expect(await repository.getCachedMeal(school, '20260725')).toBeNull();
    expect(storage.keys()).toEqual(['nyam-toss:profile:v1']);
  });

  it('drops a cache with duplicate canonical keys', async () => {
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:meal-cache:v1', JSON.stringify([
        cacheEntry(),
        cacheEntry(),
      ])],
      ['nyam-toss:progress:v1', JSON.stringify({ totalXp: 80 })],
    ]));
    const repository = new AppRepository(storage);

    expect(await repository.getCachedMeal(school, meal.date)).toBeNull();
    expect((await repository.load()).progress.totalXp).toBe(80);
    expect(storage.keys()).toEqual(['nyam-toss:progress:v1']);
  });

  it('drops a pre-seeded cache containing more than 14 entries', async () => {
    const entries = Array.from({ length: 15 }, (_, index) => {
      const cachedMeal = {
        ...meal,
        date: `202607${String(index + 1).padStart(2, '0')}`,
      };
      return cacheEntry(cachedMeal);
    });
    const storage = new MemoryStorage(new Map([
      ['nyam-toss:meal-cache:v1', JSON.stringify(entries)],
      ['nyam-toss:profile:v1', JSON.stringify(makeProfile())],
    ]));
    const repository = new AppRepository(storage);

    expect(await repository.getCachedMeal(school, '20260715')).toBeNull();
    expect((await repository.load()).profile?.nickname).toBe('냠냠이');
    expect(storage.keys()).toEqual(['nyam-toss:profile:v1']);
  });

  it('keeps exactly the 14 most recently cached live meals', async () => {
    const storage = new MemoryStorage();
    const repository = new AppRepository(storage);

    for (let day = 1; day <= 15; day += 1) {
      await repository.cacheMeal(school, {
        ...meal,
        date: `202607${String(day).padStart(2, '0')}`,
      });
    }

    const entries = JSON.parse(
      (await storage.getItem('nyam-toss:meal-cache:v1')) ?? '[]',
    );

    expect(entries).toHaveLength(14);
    expect(await repository.getCachedMeal(school, '20260701')).toBeNull();
    expect(await repository.getCachedMeal(school, '20260715'))
      .toEqual({ meal: { ...meal, date: '20260715' }, source: 'cache' });
  });

  it('does not return a cached meal for a different school or date', async () => {
    await repository.cacheMeal(school, meal);

    expect(await repository.getCachedMeal(
      { ...school, schoolCode: '7019999' },
      meal.date,
    )).toBeNull();
    expect(await repository.getCachedMeal(school, '20260725')).toBeNull();
  });

  it('does not persist sample meals', async () => {
    const storage = new MemoryStorage();
    const repository = new AppRepository(storage);

    await repository.cacheMeal(school, { ...meal, isSample: true });

    expect(await repository.getCachedMeal(school, meal.date)).toBeNull();
    expect(storage.keys()).toEqual([]);
  });

  it('round-trips valid meal records after validation', async () => {
    await repository.saveRecords([makeRecord()]);

    expect((await repository.load()).mealRecords).toEqual([makeRecord()]);
  });
});
