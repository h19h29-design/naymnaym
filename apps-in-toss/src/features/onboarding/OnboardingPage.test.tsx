import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { OnboardingPage } from './OnboardingPage';
import { AppProviders } from '../../app/AppProviders';
import { AppStateProvider } from '../../state/AppStateProvider';
import { neisClient } from '../../services/neisClient';
import type { AppRepository } from '../../services/repository';
import { school } from '../../test/fixtures';

const saveProfile = vi.fn(async () => undefined);

function Location() {
  const location = useLocation();
  return <output data-testid="location">{`${location.pathname}${location.search}`}</output>;
}

function renderOnboarding({
  searchSchools = vi.fn(async () => []),
  initialEntry = '/onboarding',
}: {
  searchSchools?: typeof neisClient.searchSchools;
  initialEntry?: string;
} = {}) {
  const user = userEvent.setup();
  vi.spyOn(neisClient, 'searchSchools').mockImplementation(searchSchools);
  const repository = {
    load: async () => ({
      profile: null,
      progress: {
        totalXp: 0,
        baseEarnedByDate: {},
        challengeEarnedByDate: {},
      },
      mealRecords: [],
      challengeRecords: [],
    }),
    saveProfile,
  } as unknown as AppRepository;

  render(
    <AppProviders>
      <MemoryRouter initialEntries={[initialEntry]}>
        <AppStateProvider repository={repository}>
          <OnboardingPage />
          <Location />
        </AppStateProvider>
      </MemoryRouter>
    </AppProviders>,
  );

  return user;
}

describe('OnboardingPage', () => {
  beforeEach(() => {
    saveProfile.mockClear();
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('requires a nickname, school, and supported school type', async () => {
    const user = renderOnboarding();

    await user.click(screen.getByRole('button', { name: '시작하기' }));

    expect(screen.getByText('별명을 입력해 주세요.')).toBeInTheDocument();
    expect(screen.getByText('중학교 또는 고등학교를 선택해 주세요.')).toBeInTheDocument();
    expect(screen.getByText('학교를 선택해 주세요.')).toBeInTheDocument();
  });

  it('searches after a 300ms debounce and saves the selected result', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.type(screen.getByLabelText('별명'), '냠냠이');
    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByLabelText('학교 검색'), '가람');
    expect(searchSchools).not.toHaveBeenCalled();
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith('가람', expect.any(AbortSignal)));
    await user.click(await screen.findByRole('button', { name: /가람중학교/ }));
    await user.click(screen.getByRole('button', { name: '시작하기' }));

    expect(saveProfile).toHaveBeenCalledWith(expect.objectContaining({
      nickname: '냠냠이',
      school,
      schoolType: 'middle',
    }));
    expect(screen.getByTestId('location')).toHaveTextContent('/today');
  });

  it('does not request invalid school-search input and exposes an accessible empty state', async () => {
    const searchSchools = vi.fn().mockResolvedValue([]);
    const user = renderOnboarding({ searchSchools });

    await user.type(screen.getByLabelText('학교 검색'), ' ');
    expect(searchSchools).not.toHaveBeenCalled();

    await user.clear(screen.getByLabelText('학교 검색'));
    await user.type(screen.getByLabelText('학교 검색'), '가람');
    expect(await screen.findByText('검색 결과가 없어요. 학교 이름을 다시 확인해 주세요.'))
      .toBeInTheDocument();
  });

  it('filters results by the selected school type and ignores stale responses', async () => {
    let firstResolve: ((value: typeof school[]) => void) | undefined;
    const highSchool = { ...school, name: '가람고등학교', schoolType: 'high' as const };
    const searchSchools = vi.fn((keyword: string) => new Promise<typeof school[]>((resolve) => {
      if (keyword === '가람') firstResolve = resolve;
      else resolve([highSchool]);
    }));
    const user = renderOnboarding({ searchSchools });

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByLabelText('학교 검색'), '가람');
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith('가람', expect.any(AbortSignal)));
    await user.clear(screen.getByLabelText('학교 검색'));
    await user.type(screen.getByLabelText('학교 검색'), '나래');
    await user.click(screen.getByRole('radio', { name: '고등학교' }));
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith('나래', expect.any(AbortSignal)));

    firstResolve?.([school]);
    await waitFor(() => expect(screen.getByRole('button', { name: /가람고등학교/ }))
      .toBeInTheDocument());
    expect(screen.queryByRole('button', { name: /가람중학교/ })).not.toBeInTheDocument();
  });

  it('starts explicit demo only after confirmation without saving', async () => {
    const user = renderOnboarding();

    await user.click(screen.getByRole('button', { name: '학교 없이 체험해 보기' }));
    expect(screen.getByRole('dialog', { name: '체험 모드 안내' })).toHaveTextContent(
      '체험 기록은 저장되지 않고 실제 성장에 반영되지 않아요.',
    );
    await user.click(screen.getByRole('button', { name: '체험 시작' }));

    expect(saveProfile).not.toHaveBeenCalled();
    expect(screen.getByTestId('location')).toHaveTextContent('/today?demo=1');
  });

  it.each(['/\\evil.test', '/%5Cevil.test', '//evil.test', '/%2F%2Fevil.test'])
  ('rejects unsafe next destinations', async (next) => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools, initialEntry: `/onboarding?next=${next}` });

    await user.type(screen.getByLabelText('별명'), '냠냠이');
    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByLabelText('학교 검색'), '가람');
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith('가람', expect.any(AbortSignal)));
    await user.click(await screen.findByRole('button', { name: /가람중학교/ }));
    await user.click(screen.getByRole('button', { name: '시작하기' }));

    expect(screen.getByTestId('location')).toHaveTextContent('/today');
  });
});
