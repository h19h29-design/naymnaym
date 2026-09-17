import { describe, expect, it, vi } from 'vitest';
import { MEAL_COACH_SESSION_KEY, createMealReviewStore, mealReviewStorageKey, type SavedMealReview } from './repository';
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

const record: SavedMealReview = {
  savedAt: 1726000000000,
  items: [{ id: 'm0', name: '현미밥' }],
  review: {
    source: 'ai',
    reviewId: '11111111-2222-4333-8444-555555555555',
    day: '2026-09-17',
    generatedAt: '2026-09-17T01:00:00.000Z',
    model: 'deepseek-v4.1-flash',
    policyVersion: 'daily-v2',
    summary: '오늘은 밥이 있어',
    menus: [{ itemId: 'm0', nutrient: 'carbohydrate', taste: '고소해', role: '힘을 내게 해', point: '골고루 먹어' }],
    caution: '천천히 씹어 먹어',
    tip: '물도 함께 마셔',
  },
};

describe('meal review store', () => {
  it('creates one v4 session id and reuses it', async () => {
    const { map, port } = memoryStorage();
    const store = createMealReviewStore(port);
    const first = await store.sessionId();
    expect(first).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    expect(await store.sessionId()).toBe(first);
    expect(map.get(MEAL_COACH_SESSION_KEY)).toBe(first);
  });

  it('round-trips a saved review under its own cache key slot', async () => {
    const { port } = memoryStorage();
    const store = createMealReviewStore(port);
    await store.saveReview('B10|1|20260917', record);
    expect(await store.loadReview('B10|1|20260917')).toEqual(record);
    expect(await store.loadReview('B10|1|20260918')).toBeNull();
  });

  it('returns null for corrupt or malformed stored reviews without deleting anything', async () => {
    const key = mealReviewStorageKey('B10|1|20260917');
    const { map, port } = memoryStorage({ [key]: '{broken' });
    expect(await createMealReviewStore(port).loadReview('B10|1|20260917')).toBeNull();
    map.set(key, JSON.stringify({ savedAt: 1, items: [], review: { source: 'ai' } }));
    expect(await createMealReviewStore(port).loadReview('B10|1|20260917')).toBeNull();
    expect(map.has(key)).toBe(true);
  });
});
