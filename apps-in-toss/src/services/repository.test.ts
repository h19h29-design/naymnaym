import { beforeEach, describe, expect, it } from 'vitest';
import { meal, makeProfile, school } from '../test/fixtures';
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
});
