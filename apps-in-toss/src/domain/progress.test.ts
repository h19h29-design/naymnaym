import { describe, expect, it } from 'vitest';
import { applyMealStatus, getLevel, LEVELS } from './progress';
import type { MealRecord } from './types';

describe('meal XP', () => {
  it('keeps twelve logical levels and the approved thresholds', () => {
    expect(LEVELS.map((level) => level.threshold)).toEqual([0, 80, 180, 320, 500, 720, 1000, 1300, 1650, 2050, 2500, 3000]);
    expect(getLevel(3000).title).toBe('전설의 급식대장');
  });

  it('replaces the same date/menu award instead of adding another one', () => {
    const first = applyMealStatus([], { date: '20260904', menuName: '현미밥', status: 'oneBite', recordedAt: 1 });
    const edited = applyMealStatus(first, { date: '20260904', menuName: ' 현미밥 ', status: 'finished', recordedAt: 2 });
    expect(edited).toHaveLength(1);
    expect(edited[0]).toMatchObject({ identity: '20260904|현미밥', xp: 10, status: 'finished' });
  });

  it('recomputes a day cap from final records', () => {
    let records: MealRecord[] = [];
    for (let index = 0; index < 3; index += 1) {
      records = applyMealStatus(records, { date: '20260904', menuName: `반찬 ${index}`, status: 'oneBite', recordedAt: index });
    }
    expect(records.reduce((sum, record) => sum + record.xp, 0)).toBe(50);
    records = applyMealStatus(records, { date: '20260904', menuName: '반찬 0', status: 'finished', recordedAt: 9 });
    expect(records.reduce((sum, record) => sum + record.xp, 0)).toBe(46);
  });

  it('preserves untouched migrated contribution while replacing the edited identity', () => {
    const migrated: MealRecord[] = [
      { identity: '20260904|밥', date: '20260904', menuName: '밥', status: 'oneBite', xp: 18, recordedAt: 1, legacy: true },
      { identity: '20260904|국', date: '20260904', menuName: '국', status: 'finished', xp: 20, recordedAt: 2, legacy: true },
    ];
    const edited = applyMealStatus(migrated, { date: '20260904', menuName: '밥', status: 'finished', recordedAt: 3 });
    expect(edited.find((record) => record.menuName === '국')?.xp).toBe(20);
    expect(edited.find((record) => record.menuName === '밥')).toMatchObject({ xp: 10, legacy: false });
  });
});
