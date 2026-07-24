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

  it('leaves a non-empty input array and record unchanged after an update', () => {
    const first = makeRecord({ status: 'oneBite', awardedXp: 18 });
    const records = [first];
    const originalRecord = { ...first };
    const result = upsertMealRecord(records, {
      ...first,
      status: 'finished',
      awardedXp: 10,
    });

    expect(records).toEqual([originalRecord]);
    expect(records[0]).toBe(first);
    expect(result.records[0]).not.toBe(first);
  });
});
