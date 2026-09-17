import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { TDSMobileAITProvider } from '@toss/tds-mobile-ait';
import { MealReviewCard } from './MealReviewCard';
import { MealCoachError, type MealReviewResult } from '../../services/mealCoachClient';
import type { SavedMealReview } from '../../services/repository';
import type { MealDay } from '../../domain/types';

const meal: MealDay = {
  date: '20260917',
  isSample: false,
  calorie: null,
  nutrition: null,
  notice: null,
  menuItems: [
    { id: 'a', name: '현미밥', allergyCodes: [], nutrients: ['탄수화물'], tags: [], sourceRawText: '현미밥' },
    { id: 'b', name: '두부조림', allergyCodes: [5], nutrients: ['단백질'], tags: [], sourceRawText: '두부조림(5)' },
    { id: 'c', name: '사과', allergyCodes: [], nutrients: ['비타민'], tags: [], sourceRawText: '사과' },
  ],
};

const review: MealReviewResult = {
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
};

const saved: SavedMealReview = {
  savedAt: 1726000000000,
  items: [{ id: 'm0', name: '현미밥' }, { id: 'm1', name: '사과' }],
  review,
};

function fakes(overrides: { review?: unknown; saved?: SavedMealReview | null } = {}) {
  const store = {
    sessionId: vi.fn(async () => '99999999-8888-4777-8666-555555555555'),
    loadReview: vi.fn(async () => overrides.saved ?? null),
    saveReview: vi.fn(async () => {}),
  };
  const client = {
    review: vi.fn(async () => (overrides.review ?? review) as MealReviewResult),
  };
  return { store, client };
}

function setup(overrides: { review?: unknown; saved?: SavedMealReview | null; persist?: boolean; allergyCodes?: number[]; day?: MealDay } = {}) {
  const { store, client } = fakes(overrides);
  render(<TDSMobileAITProvider brandPrimaryColor="#FF8A3D"><MealReviewCard
    meal={overrides.day ?? meal}
    cacheKey="B10|1|20260917"
    allergyCodes={overrides.allergyCodes ?? [5]}
    persist={overrides.persist ?? true}
    store={store}
    client={client}
  /></TDSMobileAITProvider>);
  return { store, client };
}

describe('MealReviewCard', () => {
  it('asks for consent, sends only safe items, and renders the per-menu review', async () => {
    const { store, client } = setup();
    const button = screen.getByRole('button', { name: /오늘 식단 AI 해설/ });
    expect(button).toBeDisabled();
    await userEvent.click(screen.getByLabelText('AI 해설 받기에 동의해요'));
    expect(button).toBeEnabled();
    await userEvent.click(button);
    await waitFor(() => expect(client.review).toHaveBeenCalledOnce());
    expect(client.review).toHaveBeenCalledWith(expect.objectContaining({
      sessionId: '99999999-8888-4777-8666-555555555555',
      items: [
        { id: 'm0', name: '현미밥', nutrients: ['carbohydrate'] },
        { id: 'm1', name: '사과', nutrients: ['vitamin'] },
      ],
    }));
    expect(await screen.findByText('오늘은 밥과 과일이 있어')).toBeVisible();
    expect(screen.getByText('현미밥')).toBeVisible();
    expect(screen.getByText('탄수화물')).toBeVisible();
    expect(screen.getByText('고소해')).toBeVisible();
    expect(screen.getByText('물도 함께 마셔')).toBeVisible();
    expect(screen.getByText(/AI가 만든 해설이에요/)).toBeVisible();
    expect(store.saveReview).toHaveBeenCalledWith('B10|1|20260917', expect.objectContaining({ review }));
  });

  it('restores a saved review without asking again', async () => {
    const { client } = setup({ saved });
    expect(await screen.findByText('오늘은 밥과 과일이 있어')).toBeVisible();
    expect(screen.queryByLabelText('AI 해설 받기에 동의해요')).not.toBeInTheDocument();
    expect(client.review).not.toHaveBeenCalled();
  });

  it('falls back to the saved review when the daily limit is reached', async () => {
    const store = { sessionId: vi.fn(async () => '99999999-8888-4777-8666-555555555555'), loadReview: vi.fn(async (): Promise<SavedMealReview | null> => saved), saveReview: vi.fn(async () => {}) };
    const client = { review: vi.fn(async () => { throw new MealCoachError('DAILY_LIMIT', 'limit'); }) };
    // First load returns nothing so the consent form shows; the limit fallback re-reads storage.
    store.loadReview.mockResolvedValueOnce(null);
    render(<TDSMobileAITProvider brandPrimaryColor="#FF8A3D"><MealReviewCard meal={meal} cacheKey="B10|1|20260917" allergyCodes={[5]} persist store={store} client={client} /></TDSMobileAITProvider>);
    await userEvent.click(screen.getByLabelText('AI 해설 받기에 동의해요'));
    await userEvent.click(screen.getByRole('button', { name: /오늘 식단 AI 해설/ }));
    expect(await screen.findByText('오늘은 밥과 과일이 있어')).toBeVisible();
  });

  it('shows the daily-limit message when nothing was saved', async () => {
    const store = { sessionId: vi.fn(async () => '99999999-8888-4777-8666-555555555555'), loadReview: vi.fn(async () => null), saveReview: vi.fn(async () => {}) };
    const client = { review: vi.fn(async () => { throw new MealCoachError('DAILY_LIMIT', 'limit'); }) };
    render(<TDSMobileAITProvider brandPrimaryColor="#FF8A3D"><MealReviewCard meal={meal} cacheKey="B10|1|20260917" allergyCodes={[5]} persist store={store} client={client} /></TDSMobileAITProvider>);
    await userEvent.click(screen.getByLabelText('AI 해설 받기에 동의해요'));
    await userEvent.click(screen.getByRole('button', { name: /오늘 식단 AI 해설/ }));
    expect(await screen.findByText(/오늘의 AI 해설은 이미 확인했어요/)).toBeVisible();
    expect(store.saveReview).not.toHaveBeenCalled();
  });

  it('never persists a demo review', async () => {
    const { store, client } = setup({ persist: false, saved: null });
    await userEvent.click(screen.getByLabelText('AI 해설 받기에 동의해요'));
    await userEvent.click(screen.getByRole('button', { name: /오늘 식단 AI 해설/ }));
    expect(await screen.findByText('오늘은 밥과 과일이 있어')).toBeVisible();
    expect(client.review).toHaveBeenCalledOnce();
    expect(store.saveReview).not.toHaveBeenCalled();
  });

  it('explains when no menu is eligible for a review', () => {
    setup({ day: { ...meal, menuItems: meal.menuItems.map((item) => ({ ...item, nutrients: [] })) } });
    expect(screen.getByText('오늘 해설할 수 있는 메뉴가 없어요.')).toBeVisible();
    expect(screen.queryByRole('button', { name: /오늘 식단 AI 해설/ })).not.toBeInTheDocument();
  });
});
