import { describe, expect, it } from 'vitest';
import { addDays, formatKoreanDate, getSeoulDateKey, weekKeys } from './date';

describe('meal dates', () => {
  it('uses Seoul calendar dates around UTC midnight', () => {
    expect(getSeoulDateKey(new Date('2026-09-04T15:30:00Z'))).toBe('20260905');
  });

  it('creates seven inclusive real dates across month boundaries', () => {
    expect(weekKeys('20260928')).toEqual(['20260928', '20260929', '20260930', '20261001', '20261002', '20261003', '20261004']);
    expect(addDays('20260228', 1)).toBe('20260301');
    expect(formatKoreanDate('20260904')).toContain('9월 4일');
  });
});
