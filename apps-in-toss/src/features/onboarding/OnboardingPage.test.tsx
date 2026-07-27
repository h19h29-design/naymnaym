import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { OnboardingPage } from './OnboardingPage';
import { AppProviders } from '../../app/AppProviders';
import { AppStateProvider, useAppState } from '../../state/AppStateProvider';
import { neisClient } from '../../services/neisClient';
import type { AppRepository } from '../../services/repository';
import { makeProfile, school } from '../../test/fixtures';
import '../../styles/global.css';

const saveProfile = vi.fn(async () => undefined);

function initialState() {
  return {
    profile: null,
    progress: {
      totalXp: 0,
      baseEarnedByDate: {},
      challengeEarnedByDate: {},
    },
    mealRecords: [],
    challengeRecords: [],
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

function Location() {
  const location = useLocation();
  return <output data-testid="location">{`${location.pathname}${location.search}`}</output>;
}

function ReloadProfile() {
  const { reload } = useAppState();
  return <button onClick={() => void reload()}>프로필 다시 불러오기</button>;
}

function renderOnboarding({
  searchSchools = vi.fn(async () => []),
  initialEntry = '/onboarding',
  load = async () => initialState(),
  withReloadControl = false,
}: {
  searchSchools?: typeof neisClient.searchSchools;
  initialEntry?: string;
  load?: AppRepository['load'];
  withReloadControl?: boolean;
} = {}) {
  const user = userEvent.setup();
  vi.spyOn(neisClient, 'searchSchools').mockImplementation(searchSchools);
  const repository = {
    load,
    saveProfile,
  } as unknown as AppRepository;

  render(
    <AppProviders>
      <MemoryRouter initialEntries={[initialEntry]}>
        <AppStateProvider repository={repository}>
          <OnboardingPage />
          {withReloadControl ? <ReloadProfile /> : null}
          <Location />
        </AppStateProvider>
      </MemoryRouter>
    </AppProviders>,
  );

  return user;
}

async function selectMiddleSchool(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('별명'), '냠냠이');
  await user.click(screen.getByRole('radio', { name: '중학교' }));
  await user.type(screen.getByLabelText('학교 검색'), '가람{Enter}');
  await user.click(await screen.findByRole('button', { name: /가람중학교/ }));
}

let nativeInsertAdjacentElement: typeof HTMLElement.prototype.insertAdjacentElement;

describe('OnboardingPage', () => {
  beforeEach(() => {
    saveProfile.mockClear();
  });

  beforeAll(() => {
    nativeInsertAdjacentElement = HTMLElement.prototype.insertAdjacentElement;
    // TDS 2.5's Radix focus guard expects Granite's runtime transform in the
    // browser. JSDOM lacks it, so intercept only that exact missing position.
    HTMLElement.prototype.insertAdjacentElement = function (position, element) {
      const isValidPosition = position === 'beforebegin'
        || position === 'afterbegin'
        || position === 'beforeend'
        || position === 'afterend';
      const isMissingTdsFocusGuardPosition = this === document.body
        && !isValidPosition
        && element instanceof HTMLElement
        && element.hasAttribute('data-radix-focus-guard');
      return nativeInsertAdjacentElement.call(
        this,
        isMissingTdsFocusGuardPosition ? 'afterbegin' : position,
        element,
      );
    };
  });

  afterAll(() => {
    HTMLElement.prototype.insertAdjacentElement = nativeInsertAdjacentElement;
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('requires a nickname, school, and supported school type', async () => {
    const user = renderOnboarding();

    await user.click(screen.getByRole('button', { name: /시작하기/ }));

    expect(screen.getByText('별명을 입력해 주세요.')).toBeInTheDocument();
    expect(screen.getByText('중학교 또는 고등학교를 선택해 주세요.')).toBeInTheDocument();
    expect(screen.getByText('학교를 선택해 주세요.')).toBeInTheDocument();
  });

  it('searches on keyboard submit and saves the selected result', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.type(screen.getByLabelText('별명'), '냠냠이');
    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByLabelText('학교 검색'), '가람');
    expect(searchSchools).not.toHaveBeenCalled();
    await user.keyboard('{Enter}');
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    ));
    await user.click(await screen.findByRole('button', { name: /가람중학교/ }));
    await user.click(screen.getByRole('button', { name: /시작하기/ }));

    expect(saveProfile).toHaveBeenCalledWith(expect.objectContaining({
      nickname: '냠냠이',
      school,
      schoolType: 'middle',
    }));
    expect(screen.getByTestId('location')).toHaveTextContent('/today');
  });

  it('starts a search from a WebView-safe pressable school type control', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });
    const middleSchool = screen.getByRole('radio', { name: '중학교' });

    expect(middleSchool.tagName).toBe('BUTTON');
    await user.click(middleSchool);
    await user.type(screen.getByLabelText('학교 검색'), '가람{Enter}');

    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    ));
  });

  it('keeps the native school input outside a form and auto-searches', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    const schoolSearch = screen.getByRole('searchbox', { name: '학교 검색' });
    expect(schoolSearch.tagName).toBe('INPUT');
    expect(schoolSearch.closest('form')).toBeNull();
    await user.type(schoolSearch, '가람');

    expect(await screen.findByRole('button', { name: /가람중학교/ }, {
      timeout: 2_000,
    })).toBeInTheDocument();
    expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    );
  });

  it('automatically searches after a valid school name is entered', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByRole('searchbox', { name: '학교 검색' }), '가람');

    expect(await screen.findByRole('button', { name: /가람중학교/ }, {
      timeout: 2_000,
    })).toBeInTheDocument();
    expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    );
  });

  it('keeps a partial-name search result selected without starting another search', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.type(screen.getByRole('searchbox', { name: '학교 검색' }), '가람');
    const result = await screen.findByRole('button', { name: /가람중학교/ }, {
      timeout: 2_000,
    });
    expect(searchSchools).toHaveBeenCalledTimes(2);

    await user.click(result);
    await new Promise((resolve) => window.setTimeout(resolve, 700));

    expect(screen.getByText('선택한 학교: 가람중학교')).toBeInTheDocument();
    expect(searchSchools).toHaveBeenCalledTimes(2);
  });

  it('searches automatically without rendering a separate floating search action', () => {
    renderOnboarding();

    expect(screen.getByRole('searchbox', { name: '학교 검색' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '학교 검색하기' })).not.toBeInTheDocument();
  });

  it('finds every supported school type without a school type selection', async () => {
    const highSchool = {
      ...school,
      name: '가람고등학교',
      schoolCode: '7015678',
      schoolType: 'high' as const,
    };
    const searchSchools: typeof neisClient.searchSchools = vi.fn(
      async (_keyword, type) => (type === 'high' ? [highSchool] : []),
    );
    const user = renderOnboarding({ searchSchools });

    await user.type(screen.getByRole('searchbox', { name: '학교 검색' }), '가람');

    const result = await screen.findByRole('button', { name: /가람고등학교/ }, {
      timeout: 2_000,
    });
    await user.click(result);

    expect(screen.getByRole('radio', { name: '고등학교' }))
      .toHaveAttribute('aria-checked', 'true');
  });

  it('searches immediately when the WebView keyboard sends Enter', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({ searchSchools });

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    const schoolSearch = screen.getByRole('searchbox', { name: '학교 검색' });
    await user.type(schoolSearch, '가람{Enter}');

    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    ));
  });

  it('prefills edit mode and preserves the profile creation date when saved', async () => {
    const profile = makeProfile({
      nickname: '기존 별명',
      allergyCodes: [1],
      createdAt: '2025-01-02T03:04:05.000Z',
    });
    const user = renderOnboarding({
      initialEntry: '/onboarding?mode=edit&next=%2Fsettings',
      load: async () => ({ ...initialState(), profile }),
    });

    expect(await screen.findByDisplayValue('기존 별명')).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: '중학교' })).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByText('선택한 학교: 가람중학교')).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: '난류' })).toHaveAttribute('aria-checked', 'true');

    await user.clear(screen.getByLabelText('별명'));
    await user.type(screen.getByLabelText('별명'), '바꾼 별명');
    await user.click(screen.getByRole('button', { name: '시작하기' }));

    expect(saveProfile).toHaveBeenCalledWith(expect.objectContaining({
      nickname: '바꾼 별명',
      createdAt: '2025-01-02T03:04:05.000Z',
    }));
    expect(screen.getByTestId('location')).toHaveTextContent('/settings');
  });

  it('does not clobber an active edit when the provider reloads a profile', async () => {
    const first = makeProfile({ nickname: '기존 별명' });
    const refreshed = makeProfile({ nickname: '새로 불러온 별명' });
    const load = vi.fn()
      .mockResolvedValueOnce({ ...initialState(), profile: first })
      .mockResolvedValueOnce({ ...initialState(), profile: refreshed });
    const user = renderOnboarding({
      initialEntry: '/onboarding?mode=edit&next=%2Fsettings',
      load,
      withReloadControl: true,
    });

    const nickname = await screen.findByDisplayValue('기존 별명');
    await user.clear(nickname);
    await user.type(nickname, '작성 중인 별명');
    await user.click(screen.getByRole('button', { name: '프로필 다시 불러오기' }));

    expect(screen.getByLabelText('별명')).toHaveValue('작성 중인 별명');
  });

  it('does not request invalid school-search input and exposes an accessible empty state', async () => {
    const searchSchools = vi.fn().mockResolvedValue([]);
    const user = renderOnboarding({ searchSchools });

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    await user.type(screen.getByLabelText('학교 검색'), ' {Enter}');
    expect(searchSchools).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent(
      '학교 이름을 두 글자 이상 입력해 주세요.',
    );

    await user.clear(screen.getByLabelText('학교 검색'));
    await user.type(screen.getByLabelText('학교 검색'), '가람{Enter}');
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
    await user.type(screen.getByLabelText('학교 검색'), '가람{Enter}');
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith(
      '가람',
      'middle',
      expect.any(AbortSignal),
    ));
    await user.clear(screen.getByLabelText('학교 검색'));
    await user.type(screen.getByLabelText('학교 검색'), '나래');
    await user.click(screen.getByRole('radio', { name: '고등학교' }));
    await user.type(screen.getByLabelText('학교 검색'), '{Enter}');
    await waitFor(() => expect(searchSchools).toHaveBeenCalledWith(
      '나래',
      'high',
      expect.any(AbortSignal),
    ));

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

  it.each([
    '/\\evil.test',
    '/%5Cevil.test',
    '//evil.test',
    '/%2F%2Fevil.test',
    '/onboarding',
    '/onboarding?next=/today',
    '/%6fnboarding',
    '/%256fnboarding',
  ])
  ('rejects unsafe next destinations', async (next) => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const user = renderOnboarding({
      searchSchools,
      initialEntry: `/onboarding?next=${encodeURIComponent(next)}`,
    });

    await selectMiddleSchool(user);
    await user.click(screen.getByRole('button', { name: /시작하기/ }));

    expect(screen.getByTestId('location')).toHaveTextContent('/today');
  });

  it('toggles representative school and allergy choices when their visible labels are clicked', async () => {
    const user = renderOnboarding();

    await user.click(screen.getByRole('radio', { name: '중학교' }));
    expect(screen.getByRole('radio', { name: '중학교' })).toHaveAttribute('aria-checked', 'true');

    await user.click(screen.getByText('난류', { selector: 'label' }));
    expect(screen.getByRole('checkbox', { name: '난류' })).toHaveAttribute('aria-checked', 'true');

    await user.click(screen.getByText('해당 없음', { selector: 'label' }));
    expect(screen.getByRole('checkbox', { name: '난류' })).toHaveAttribute('aria-checked', 'false');
    expect(screen.getByRole('checkbox', { name: '해당 없음' })).toHaveAttribute('aria-checked', 'true');
  });

  it('prevents concurrent profile saves while a submission is pending', async () => {
    const pendingSave = deferred<undefined>();
    const searchSchools = vi.fn().mockResolvedValue([school]);
    saveProfile.mockImplementation(() => pendingSave.promise);
    const user = renderOnboarding({ searchSchools });

    await selectMiddleSchool(user);
    const start = screen.getByRole('button', { name: '시작하기' });
    await user.dblClick(start);

    expect(saveProfile).toHaveBeenCalledTimes(1);
    expect(start).toBeDisabled();
    pendingSave.resolve(undefined);
    await waitFor(() => {
      expect(screen.getByTestId('location')).toHaveTextContent('/today');
    });
  });

  it('shows a save error and permits a retry', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    saveProfile.mockRejectedValueOnce(new Error('write failed')).mockResolvedValueOnce(undefined);
    const user = renderOnboarding({ searchSchools });

    await selectMiddleSchool(user);
    await user.click(screen.getByRole('button', { name: /시작하기/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      '프로필을 저장하지 못했어요. 다시 시도해 주세요.',
    );

    await user.click(screen.getByRole('button', { name: /시작하기/ }));
    expect(saveProfile).toHaveBeenCalledTimes(2);
    expect(await screen.findByTestId('location')).toHaveTextContent('/today');
  });

  it('locks the saved profile and retries only reload after reload fails', async () => {
    const searchSchools = vi.fn().mockResolvedValue([school]);
    const load = vi.fn()
      .mockResolvedValueOnce(initialState())
      .mockRejectedValueOnce(new Error('read failed'))
      .mockResolvedValueOnce(initialState());
    const user = renderOnboarding({ searchSchools, load });

    await selectMiddleSchool(user);
    await user.click(screen.getByRole('button', { name: '시작하기' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      '프로필은 저장되었어요. 정보를 다시 불러오면 시작할 수 있어요.',
    );
    expect(saveProfile).toHaveBeenCalledTimes(1);

    const nickname = screen.getByLabelText('별명');
    const middleSchool = screen.getByRole('radio', { name: '중학교' });
    const highSchool = screen.getByRole('radio', { name: '고등학교' });
    const schoolSearch = screen.getByLabelText('학교 검색');
    const schoolResult = screen.getByRole('button', { name: /가람중학교/ });
    const allergy = screen.getByRole('checkbox', { name: '난류' });
    const demo = screen.getByRole('button', { name: '학교 없이 체험해 보기' });

    expect(nickname).toBeDisabled();
    expect(middleSchool).toBeDisabled();
    expect(highSchool).toBeDisabled();
    expect(schoolSearch).toBeDisabled();
    expect(schoolResult).toBeDisabled();
    expect(allergy).toHaveAttribute('aria-disabled', 'true');
    expect(demo).toBeDisabled();

    await user.type(nickname, '변경');
    await user.click(highSchool);
    await user.type(schoolSearch, '나래');
    await user.click(allergy);

    expect(nickname).toHaveValue('냠냠이');
    expect(middleSchool).toHaveAttribute('aria-checked', 'true');
    expect(highSchool).toHaveAttribute('aria-checked', 'false');
    expect(schoolSearch).toHaveValue('가람중학교');
    expect(allergy).toHaveAttribute('aria-checked', 'false');
    expect(screen.getByText('선택한 학교: 가람중학교')).toBeInTheDocument();
    expect(screen.queryByRole('dialog', { name: '체험 모드 안내' })).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /다시 불러오기/ }));
    expect(saveProfile).toHaveBeenCalledTimes(1);
    expect(await screen.findByTestId('location')).toHaveTextContent('/today');
  });
});
