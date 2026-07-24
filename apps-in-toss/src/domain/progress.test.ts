import { describe, expect, it } from 'vitest';
import { makeRecord } from '../test/fixtures';
import { calculateXp, hasPreviousDayRecord, levelFor } from './progress';

describe('progress rules', () => {
  it('applies retry XP and the base cap', () => {
    expect(calculateXp({
      status: 'oneBite',
      previousStatus: 'difficultToday',
      baseEarnedToday: 40,
      challengeEarnedToday: 0,
      variedFoodGroup: false,
      streakRecord: false,
      allergySafetyCheck: false,
    })).toEqual({ base: 10, challenge: 25, total: 35 });
  });

  it('applies challenge and combined daily caps after base XP', () => {
    expect(calculateXp({
      status: 'oneBite',
      previousStatus: null,
      baseEarnedToday: 40,
      challengeEarnedToday: 50,
      variedFoodGroup: true,
      streakRecord: true,
      allergySafetyCheck: true,
    })).toEqual({ base: 10, challenge: 0, total: 10 });
  });

  it('only applies retry XP after difficultToday', () => {
    expect(calculateXp({
      status: 'finished',
      previousStatus: 'smelledOnly',
      baseEarnedToday: 0,
      challengeEarnedToday: 0,
      variedFoodGroup: false,
      streakRecord: false,
      allergySafetyCheck: false,
    })).toEqual({ base: 10, challenge: 0, total: 10 });
  });

  it('maps thresholds to the seven approved levels', () => {
    expect(levelFor(0).title).toBe('냠냠 새싹');
    expect(levelFor(180).title).toBe('냠냠 용사');
    expect(levelFor(1_000).title).toBe('레전드 냠냠러');
  });

  it('recognizes only the immediately previous date as a streak', () => {
    expect(hasPreviousDayRecord([makeRecord({ date: '20260723' })], '20260724'))
      .toBe(true);
    expect(hasPreviousDayRecord([makeRecord({ date: '20260722' })], '20260724'))
      .toBe(false);
  });

  it('recognizes the previous calendar day across a month boundary', () => {
    expect(hasPreviousDayRecord([makeRecord({ date: '20260228' })], '20260301'))
      .toBe(true);
  });
});
