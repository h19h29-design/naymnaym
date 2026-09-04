import { describe, expect, it, vi } from 'vitest';
import { LEGACY_KEYS, STATE_KEY, createRepository } from './repository';
import type { StoragePort } from './storage';

function memoryStorage(seed: Record<string, string> = {}) {
  const map = new Map(Object.entries(seed));
  const port: StoragePort = {
    getItem: vi.fn(async (key) => map.get(key) ?? null),
    setItem: vi.fn(async (key, value) => { map.set(key, value); }),
    clearItems: vi.fn(async () => { map.clear(); }),
  };
  return { map, port };
}

describe('v2 repository', () => {
  it('migrates legacy profile, records, cache, and total XP atomically without deleting legacy keys', async () => {
    const { map, port } = memoryStorage({
      [LEGACY_KEYS.profile]: JSON.stringify({ nickname: '냠냠이', school: { name: '한빛중', officeCode: 'B10', schoolCode: '1', region: '서울', address: '서울', schoolType: 'middle' }, allergyCodes: [1, 12] }),
      [LEGACY_KEYS.progress]: JSON.stringify({ totalXp: 123 }),
      [LEGACY_KEYS.records]: JSON.stringify([{ date: '20260904', mealItemId: 'm', mealName: '밥', status: 'oneBite', awardedXp: 18, recordedAt: '2026-09-04T03:00:00.000Z' }]),
      [LEGACY_KEYS.cache]: JSON.stringify([{ key: 'B10:1:20260904', meal: { date: '20260904', menuItems: [], calorie: null, nutrition: null, isSample: false, notice: null }, savedAt: '2026-09-04T03:00:00.000Z' }]),
    });
    const state = await createRepository(port).load();
    expect(state.totalXP).toBe(123);
    expect(state.profile?.school.schoolType).toBe('middle');
    expect(state.mealRecords).toHaveLength(1);
    expect(state.mealRecords[0]).toMatchObject({ menuName: '밥', status: 'oneBite', xp: 18, legacy: true });
    expect(state.cache?.key).toBe('B10|1|20260904');
    expect(map.has(STATE_KEY)).toBe(true);
    expect(map.has(LEGACY_KEYS.profile)).toBe(true);
    expect(port.clearItems).not.toHaveBeenCalled();
  });

  it('is idempotent and recovers corrupt v2 data without deleting anything', async () => {
    const { map, port } = memoryStorage({ [STATE_KEY]: '{nope', [LEGACY_KEYS.progress]: JSON.stringify({ totalXp: 40 }) });
    const repo = createRepository(port);
    expect((await repo.load()).totalXP).toBe(40);
    expect((await repo.load()).totalXP).toBe(40);
    expect(map.has(LEGACY_KEYS.progress)).toBe(true);
    expect(port.clearItems).not.toHaveBeenCalled();
  });

  it('only clears all official Storage data after the explicit delete method is called', async () => {
    const { port } = memoryStorage();
    await createRepository(port).clearAllConfirmed();
    expect(port.clearItems).toHaveBeenCalledOnce();
  });

  it('maps every evidenced v1 eating status without losing awarded XP', async () => {
    const legacy = [
      ['finished', 'finished', 10],
      ['half', 'oneBite', 12],
      ['oneBite', 'oneBite', 18],
      ['smelledOnly', 'skipped', 10],
      ['difficultToday', 'skipped', 3],
      ['allergyAvoided', 'skipped', 8],
    ] as const;
    const records = legacy.map(([status, , awardedXp], index) => ({
      date: `2026090${index + 1}`, mealItemId: `m${index}`, mealName: `메뉴 ${index}`,
      status, awardedXp, recordedAt: `2026-09-0${index + 1}T03:00:00.000Z`,
    }));
    const totalXp = legacy.reduce((sum, [, , xp]) => sum + xp, 40);
    const { map, port } = memoryStorage({
      [LEGACY_KEYS.progress]: JSON.stringify({ totalXp }),
      [LEGACY_KEYS.records]: JSON.stringify(records),
    });
    const repo = createRepository(port);
    const first = await repo.load();
    expect(first.mealRecords.map((record) => record.status)).toEqual(legacy.map(([, mapped]) => mapped));
    expect(first.mealRecords.map((record) => record.xp)).toEqual(legacy.map(([, , xp]) => xp));
    expect(first.totalXP).toBe(totalXp);
    expect(first.xpBaseline).toBe(40);
    expect(await repo.load()).toEqual(first);
    expect(map.has(LEGACY_KEYS.records)).toBe(true);
  });
});
