import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { AppRoutes } from './App';
import { AppProviders } from './AppProviders';
import { AppStateProvider } from '../state/AppStateProvider';
import { EMPTY_STATE } from '../services/repository';
import type { AppState } from '../domain/types';
import { NeisClientError } from '../services/neisClient';
import { getSeoulDateKey, weekKeys } from '../domain/date';
import { recordIdentity } from '../domain/progress';

const school = { name: '한빛초등학교', officeCode: 'B10', schoolCode: '123', region: '서울', address: '서울 마포구', schoolType: 'elementary' as const };
const meal = { date: '20260904', menuItems: [{ id: 'm1', name: '현미밥', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '현미밥' }], calorie: null, nutrition: null, isSample: false, notice: null };

function setup(path: string, state: AppState = EMPTY_STATE, overrides: Record<string, unknown> = {}) {
  const repository = { load: vi.fn(async () => state), save: vi.fn(async () => {}), clearAllConfirmed: vi.fn(async () => {}) };
  const client = {
    searchSchools: vi.fn(async () => [school]),
    fetchMeals: vi.fn(async () => meal),
    fetchMealsRange: vi.fn(async () => [meal]),
    ...overrides,
  };
  render(<AppProviders><AppStateProvider repository={repository} client={client as never}><MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter></AppStateProvider></AppProviders>);
  return { repository, client };
}

describe('lite routes', () => {
  it('completes elementary onboarding with optional nickname and allergies', async () => {
    const { repository } = setup('/onboarding');
    await screen.findByRole('heading', { name: '학교 급식으로 레벨업해요' });
    expect(screen.getByLabelText('초등학교')).toBeChecked();
    expect(screen.getByLabelText('중학교')).toBeVisible();
    expect(screen.getByLabelText('고등학교')).toBeVisible();
    await userEvent.type(screen.getByLabelText('학교 이름'), '한빛');
    await userEvent.click(screen.getByRole('button', { name: '학교 검색' }));
    expect(await screen.findByText('서울 · 초등학교')).toBeVisible();
    await userEvent.click(await screen.findByRole('button', { name: /한빛초등학교 선택/ }));
    await userEvent.click(screen.getByLabelText('우유'));
    await userEvent.click(screen.getByRole('button', { name: '시작하기' }));
    await waitFor(() => expect(repository.save).toHaveBeenCalledWith(expect.objectContaining({
      profile: expect.objectContaining({ nickname: '냠냠이', school, allergyCodes: [2] }),
    })));
  });

  it('shows today growth and meal, then replaces the menu status', async () => {
    const state: AppState = { ...EMPTY_STATE, profile: { nickname: '나', school, allergyCodes: [] } };
    const { repository } = setup('/today', state);
    expect(await screen.findByRole('heading', { name: /오늘의 급식/ })).toBeVisible();
    expect(screen.getByText('냠냠 새싹')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: '현미밥 한 입 도전' }));
    await waitFor(() => expect(repository.save).toHaveBeenLastCalledWith(expect.objectContaining({ totalXP: 18 })));
    expect(screen.getByText('기록했어요! XP가 새 상태로 반영됐어요.')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: '현미밥 잘 먹음' }));
    await waitFor(() => expect(repository.save).toHaveBeenLastCalledWith(expect.objectContaining({ totalXP: 10 })));
  });

  it('calls one seven-day range and renders all dates including no-meal days', async () => {
    const state: AppState = { ...EMPTY_STATE, profile: { nickname: '나', school, allergyCodes: [] } };
    const { client } = setup('/week', state);
    expect(await screen.findByRole('heading', { name: '이번 주 급식' })).toBeVisible();
    await waitFor(() => expect(client.fetchMealsRange).toHaveBeenCalledOnce());
    const dates = weekKeys(getSeoulDateKey());
    expect(client.fetchMealsRange).toHaveBeenCalledWith(expect.objectContaining({ fromDate: dates[0], toDate: dates[6] }));
    expect(screen.getAllByTestId('week-day')).toHaveLength(7);
    expect(screen.getAllByText('급식이 없어요').length).toBeGreaterThanOrEqual(6);
  });

  it('requires confirmation before clearing official Storage', async () => {
    const state: AppState = { ...EMPTY_STATE, profile: { nickname: '나', school, allergyCodes: [] } };
    const { repository } = setup('/settings', state);
    await screen.findByRole('heading', { name: '설정' });
    expect(screen.getByRole('heading', { name: '앱 정보' })).toBeVisible();
    expect(screen.getByText('급식레벨업 Lite v2')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: '모든 데이터 삭제' }));
    expect(repository.clearAllConfirmed).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: '삭제할게요' }));
    expect(repository.clearAllConfirmed).toHaveBeenCalledOnce();
  });

  it('shows a distinct network state and never persists explicit demo choices', async () => {
    const state: AppState = { ...EMPTY_STATE, profile: { nickname: '나', school, allergyCodes: [] } };
    const { repository } = setup('/today', state, { fetchMeals: vi.fn(async () => { throw new NeisClientError('NETWORK', 'offline'); }) });
    expect(await screen.findByText('네트워크 연결을 확인하고 다시 시도해 주세요.')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: '체험 급식 보기' }));
    expect(screen.getByText('체험 급식의 선택과 XP는 저장되지 않아요.')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: '귀리밥 잘 먹음' }));
    expect(repository.save).not.toHaveBeenCalled();
  });

  it('shows a saved status for canonically equivalent NFC and whitespace menu names', async () => {
    const menuName = '김치   볶음밥';
    const canonical = '김치 볶음밥';
    const canonicalMeal = { ...meal, menuItems: [{ ...meal.menuItems[0], id: 'canonical', name: menuName, sourceRawText: menuName }] };
    const state: AppState = {
      ...EMPTY_STATE,
      profile: { nickname: '나', school, allergyCodes: [] },
      mealRecords: [{ identity: recordIdentity(meal.date, canonical), date: meal.date, menuName: canonical, status: 'oneBite', xp: 18, recordedAt: 1 }],
      totalXP: 18,
    };
    setup('/today', state, { fetchMeals: vi.fn(async () => canonicalMeal) });
    const button = (await screen.findByText('한 입 도전')).closest('button');
    expect(button).not.toBeNull();
    expect(button).toHaveAttribute('aria-pressed', 'true');
  });

  it('uses a newly saved live cache when a later refresh fails in the same mount', async () => {
    const state: AppState = { ...EMPTY_STATE, profile: { nickname: '나', school, allergyCodes: [] } };
    const fetchMeals = vi.fn().mockResolvedValueOnce(meal).mockRejectedValueOnce(new NeisClientError('NETWORK', 'offline'));
    const { client } = setup('/today', state, { fetchMeals });
    expect(await screen.findByText('학교 급식')).toBeVisible();
    await waitFor(() => expect(client.fetchMeals).toHaveBeenCalledOnce());
    await userEvent.click(screen.getByRole('button', { name: '급식 새로고침' }));
    expect(await screen.findByText('저장된 급식')).toBeVisible();
    expect(screen.getByText(/저장된 급식을 보여드려요/)).toBeVisible();
    expect(client.fetchMeals).toHaveBeenCalledTimes(2);
  });
});
