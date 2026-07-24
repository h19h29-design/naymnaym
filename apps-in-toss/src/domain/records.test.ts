import { describe, expect, it } from 'vitest';
import { makeRecord } from '../test/fixtures';
import { upsertMealRecord } from './records';

describe('meal records', () => {
  it('updates the status but never awards duplicate XP for the same menu and date', () => {
    const first = makeRecord({ status: 'oneBite', awardedXp: 18 });
    const updated = upsertMealRecord([first], {
      ...first,
      status: 'finished',
      awardedXp: 10,
    });

    expect(updated.records).toHaveLength(1);
    expect(updated.records[0].status).toBe('finished');
    expect(updated.records[0].awardedXp).toBe(18);
    expect(updated.newXp).toBe(0);
  });

  it('awards XP for a first record and leaves the input list unchanged', () => {
    const first = makeRecord();
    const result = upsertMealRecord([], first);

    expect(result).toEqual({ records: [first], newXp: 18 });
  });
});
