import { afterEach, describe, expect, it, vi } from 'vitest';
import type { MealItem } from '../domain/types';
import {
  MealCoachError,
  buildReviewItems,
  createMealCoachClient,
  mealCoachErrorMessage,
  normalizeNutrients,
  validMenuName,
  type MealReviewResult,
} from './mealCoachClient';

afterEach(() => vi.unstubAllGlobals());

const item = (partial: Partial<MealItem>): MealItem => ({
  id: 'x', name: '메뉴', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '메뉴', ...partial,
});

describe('review item building', () => {
  it('maps Korean nutrient labels to ids, dedupes, and keeps the canonical order', () => {
    expect(normalizeNutrients(['단백질', '식이섬유', '단백질', 'other'])).toEqual(['fiber', 'protein']);
    expect(normalizeNutrients(['칼슘', 'vitamin'])).toEqual(['vitamin', 'calcium']);
  });

  it('accepts only server-safe menu names', () => {
    expect(validMenuName(' 카레라이스 ')).toBe(true);
    expect(validMenuName('')).toBe(false);
    expect(validMenuName('12345')).toBe(false);
    expect(validMenuName('a'.repeat(31))).toBe(false);
    expect(validMenuName('메뉴<1>')).toBe(false);
    expect(validMenuName('메뉴[2]')).toBe(false);
    expect(validMenuName('see http://x')).toBe(false);
    expect(validMenuName('메뉴\u0001')).toBe(false);
  });

  it('drops allergy-risk, unnamed, and nutrient-less menus, then renumbers sequentially', () => {
    const items = buildReviewItems([
      item({ id: 'a', name: '현미밥', nutrients: ['탄수화물'] }),
      item({ id: 'b', name: '우유', allergyCodes: [2], nutrients: ['칼슘'] }),
      item({ id: 'c', name: '???', nutrients: ['비타민'] }),
      item({ id: 'd', name: '사과', nutrients: [] }),
      item({ id: 'e', name: '두부조림', nutrients: ['단백질', '철분'] }),
    ], [2]);
    expect(items).toEqual([
      { id: 'm0', name: '현미밥', nutrients: ['carbohydrate'] },
      { id: 'm1', name: '두부조림', nutrients: ['protein', 'iron'] },
    ]);
  });

  it('caps the request at fifteen items', () => {
    const items = buildReviewItems(
      Array.from({ length: 20 }, (_, index) => item({ id: String(index), name: `메뉴${index}`, nutrients: ['비타민'] })),
      [],
    );
    expect(items).toHaveLength(15);
    expect(items[14].id).toBe('m14');
  });
});

const reviewItems = [
  { id: 'm0', name: '현미밥', nutrients: ['carbohydrate' as const] },
  { id: 'm1', name: '사과', nutrients: ['vitamin' as const] },
];

function okResponse(overrides: Record<string, unknown> = {}) {
  return {
    source: 'ai',
    reviewId: '11111111-2222-4333-8444-555555555555',
    day: '2026-09-17',
    generatedAt: '2026-09-17T01:00:00.000Z',
    model: 'deepseek-v4.1-flash',
    policyVersion: 'daily-v2',
    summary: '오늘은 밥과 과일이 있어',
    menus: [
      { itemId: 'm0', nutrient: 'carbohydrate', taste: '고소해', role: '힘을 내게 해', point: '골고루 먹어' },
      { itemId: 'm1', nutrient: 'vitamin', taste: '달콤해', role: '몸을 지켜줘', point: '남기지 말아' },
    ],
    caution: '천천히 씹어 먹어',
    tip: '물도 함께 마셔',
    ...overrides,
  };
}

function stubFetch(body: unknown, init: { ok?: boolean; status?: number } = {}) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  return vi.fn().mockResolvedValue({ ok: init.ok ?? true, status: init.status ?? 200, text: async () => text });
}

const REQUEST = { requestId: '11111111-2222-4333-8444-555555555555', sessionId: '99999999-8888-4777-8666-555555555555', items: reviewItems };

describe('meal coach client', () => {
  it('posts only the anonymous review payload as JSON', async () => {
    const fetchMock = stubFetch(okResponse());
    vi.stubGlobal('fetch', fetchMock);
    const client = createMealCoachClient({ url: 'https://coach.example' });
    const result = await client.review(REQUEST);
    expect(fetchMock).toHaveBeenCalledWith('https://coach.example', expect.objectContaining({
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }));
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({
      requestId: REQUEST.requestId,
      sessionId: REQUEST.sessionId,
      items: reviewItems,
      wholeMeal: {},
    });
    expect(result.menus.map((menu) => menu.itemId)).toEqual(['m0', 'm1']);
  });

  it('rejects a response whose review id or menu coverage does not match the request', async () => {
    const client = createMealCoachClient({ url: 'https://coach.example' });
    vi.stubGlobal('fetch', stubFetch(okResponse({ reviewId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' })));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'INVALID_RESPONSE' });
    vi.stubGlobal('fetch', stubFetch(okResponse({ menus: okResponse().menus.slice(0, 1) })));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'INVALID_RESPONSE' });
    vi.stubGlobal('fetch', stubFetch(okResponse({ menus: [{ itemId: 'm0', nutrient: 'vitamin', taste: 'a', role: 'b', point: 'c' }, okResponse().menus[1]] })));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'INVALID_RESPONSE' });
  });

  it('maps http failures to distinct kinds', async () => {
    const client = createMealCoachClient({ url: 'https://coach.example' });
    vi.stubGlobal('fetch', stubFetch({ error: 'daily_attempt_limit' }, { ok: false, status: 429 }));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'DAILY_LIMIT' });
    vi.stubGlobal('fetch', stubFetch({ error: 'global_limit' }, { ok: false, status: 429 }));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'GLOBAL_LIMIT' });
    vi.stubGlobal('fetch', stubFetch({ error: 'invalid_request' }, { ok: false, status: 400 }));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'INVALID_REQUEST' });
    vi.stubGlobal('fetch', stubFetch({}, { ok: false, status: 503 }));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'UNAVAILABLE' });
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('offline')));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'NETWORK' });
    vi.stubGlobal('fetch', stubFetch('not json'));
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'INVALID_RESPONSE' });
  });

  it('rejects an oversized response body', async () => {
    vi.stubGlobal('fetch', stubFetch('x'.repeat(17 * 1024)));
    const client = createMealCoachClient({ url: 'https://coach.example' });
    await expect(client.review(REQUEST)).rejects.toMatchObject({ kind: 'TOO_LARGE' });
  });

  it('gives the daily limit a distinct user message', () => {
    expect(mealCoachErrorMessage(new MealCoachError('DAILY_LIMIT', 'x'))).toContain('이미 확인했어요');
    expect(mealCoachErrorMessage(new MealCoachError('NETWORK', 'x'))).toContain('네트워크');
  });
});
