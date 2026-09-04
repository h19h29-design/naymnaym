import { describe, expect, it } from 'vitest';
import { addDays, formatKoreanDate, getSeoulDateKey, weekKeys } from './date';

describe('meal dates', () => {
  it('uses Seoul calendar dates around UTC midnight', () => {
    expect(getSeoulDateKey(new Date('2026-09-04T15:30:00Z'))).toBe('20260905');
  });

  it('creates seven inclusive real dates across month boundaries', () => {
    expect(weekKeys('20261001')).toEqual(['20260928', '20260929', '20260930', '20261001', '20261002', '20261003', '20261004']);
    expect(addDays('20260228', 1)).toBe('20260301');
    expect(formatKoreanDate('20260904')).toContain('9월 4일');
  });

  it('uses the native ko-KR Monday-to-Sunday school week at Seoul boundaries', () => {
    expect(weekKeys(getSeoulDateKey(new Date('2026-09-06T14:59:59Z')))).toEqual(['20260831', '20260901', '20260902', '20260903', '20260904', '20260905', '20260906']);
    expect(weekKeys(getSeoulDateKey(new Date('2026-09-06T15:00:00Z')))).toEqual(['20260907', '20260908', '20260909', '20260910', '20260911', '20260912', '20260913']);
  });
});
