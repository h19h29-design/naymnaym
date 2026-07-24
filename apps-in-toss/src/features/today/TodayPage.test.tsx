import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { loadTodayMeal, seoulDate, type TodayMealResult } from './useTodayMeal';
import type { AppRepository } from '../../services/repository';
import type { AppState } from '../../state/reducer';
import { meal, mealWithAllergen, makeProfile } from '../../test/fixtures';
import { TodayPage } from './TodayPage';
import { AppProviders } from '../../app/AppProviders';

const useTodayMeal = vi.fn();
const reload = vi.fn(async () => true);
const saveRecords = vi.fn(async () => undefined);
const saveProgress = vi.fn(async () => undefined);
const saveChallengeRecords = vi.fn(async () => undefined);

let appState: AppState;
let initialRoute = '/today';
let nativeInsertAdjacentElement: typeof HTMLElement.prototype.insertAdjacentElement;

vi.mock('./useTodayMeal', async () => ({
  ...await vi.importActual('./useTodayMeal'),
  useTodayMeal: (...args: unknown[]) => useTodayMeal(...args),
}));

vi.mock('../../state/AppStateProvider', () => ({
  useAppState: () => ({
    state: appState,
    repository: {
      saveRecords,
      saveProgress,
      saveChallengeRecords,
    } as unknown as AppRepository,
    reload,
  }),
}));

vi.mock('../../services/neisClient', async () => ({
  ...await vi.importActual('../../services/neisClient'),
  neisClient: {},
}));

function readyState(allergies: number[] = []): AppState {
  return {
    status: 'ready',
    profile: makeProfile({ allergyCodes: allergies }),
    progress: { totalXp: 0, baseEarnedByDate: {}, challengeEarnedByDate: {} },
    mealRecords: [],
    challengeRecords: [],
  };
}

function renderToday({
  mealResult = { kind: 'live', meal },
  allergies = [],
  route = '/today',
}: {
  mealResult?: TodayMealResult;
  allergies?: number[];
  route?: string;
} = {}) {
  appState = readyState(allergies);
  useTodayMeal.mockReturnValue({ result: mealResult, retry: vi.fn() });
  initialRoute = route;
  return userEvent.setup();
}

function renderPage() {
  return render(
    <AppProviders>
      <MemoryRouter initialEntries={[initialRoute]}>
        <TodayPage />
      </MemoryRouter>
    </AppProviders>,
  );
}

describe('TodayPage', () => {
  beforeAll(() => {
    nativeInsertAdjacentElement = HTMLElement.prototype.insertAdjacentElement;
    HTMLElement.prototype.insertAdjacentElement = function (position, element) {
      const valid = position === 'beforebegin' || position === 'afterbegin'
        || position === 'beforeend' || position === 'afterend';
      const focusGuard = this === document.body && element instanceof HTMLElement
        && element.hasAttribute('data-radix-focus-guard');
      return nativeInsertAdjacentElement.call(this, !valid && focusGuard ? 'afterbegin' : position, element);
    };
  });

  afterAll(() => {
    HTMLElement.prototype.insertAdjacentElement = nativeInsertAdjacentElement;
  });

  beforeEach(() => {
    appState = readyState();
    useTodayMeal.mockReset();
    reload.mockClear();
    saveRecords.mockClear();
    saveProgress.mockClear();
    saveChallengeRecords.mockClear();
  });

  afterEach(cleanup);

  it('labels cached live data and does not call it sample data', async () => {
    const user = renderToday({ mealResult: { kind: 'cache', meal } });
    renderPage();

    expect(await screen.findByText('저장된 급식 정보예요')).toBeInTheDocument();
    expect(screen.queryByText(/체험/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '한입도전' }));
  });

  it('shows an error instead of silently replacing live data with demo data', async () => {
    renderToday({ mealResult: { kind: 'error', code: 'UPSTREAM_ERROR' } });
    renderPage();

    expect(await screen.findByText('급식 정보를 불러오지 못했어요')).toBeInTheDocument();
    expect(screen.queryByText('체험 급식')).not.toBeInTheDocument();
  });

  it('never persists a demo meal record or XP', async () => {
    const user = renderToday({ mealResult: { kind: 'demo', meal }, route: '/today?demo=1' });
    renderPage();

    await user.click(await screen.findByRole('button', { name: '한입도전' }));

    expect(saveRecords).not.toHaveBeenCalled();
    expect(saveProgress).not.toHaveBeenCalled();
    expect(saveChallengeRecords).not.toHaveBeenCalled();
    expect(reload).not.toHaveBeenCalled();
    expect(screen.getByText('체험 기록을 남겼어요. 이 기록은 저장되지 않아요.')).toBeInTheDocument();
  });

  it('replaces one-bite with allergy avoidance for a risky item', async () => {
    renderToday({
      allergies: [6],
      mealResult: { kind: 'live', meal: mealWithAllergen(6) },
    });
    renderPage();

    expect(await screen.findByRole('button', { name: '알레르기 때문에 피했어요' }))
      .toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '한입도전' })).not.toBeInTheDocument();
    expect(screen.getByRole('note')).toHaveTextContent('밀');
  });

  it('opens difficulty reasons only after the user asks', async () => {
    const user = renderToday();
    renderPage();

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    await user.click(await screen.findByRole('button', { name: '못먹겠어요' }));
    expect(screen.getByRole('dialog', { name: '어떤 점이 어려웠나요?' }))
      .toBeInTheDocument();
  });

  it('records a deliberately selected difficulty reason', async () => {
    const user = renderToday();
    renderPage();

    await user.click(await screen.findByRole('button', { name: '못먹겠어요' }));
    await user.click(screen.getByRole('button', { name: '냄새' }));
    await user.click(screen.getByRole('button', { name: '오늘은 어려웠어요' }));

    await waitFor(() => expect(saveRecords).toHaveBeenCalledWith([
      expect.objectContaining({ status: 'difficultToday', difficultyReason: 'smell' }),
    ]));
  });

  it('announces a save error and allows retry without duplicate XP', async () => {
    saveRecords.mockRejectedValueOnce(new Error('storage failed'));
    const user = renderToday();
    renderPage();

    await user.click(await screen.findByRole('button', { name: '한입도전' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('기록을 저장하지 못했어요. 다시 시도해 주세요.');
    await user.click(screen.getByRole('button', { name: '다시 시도' }));

    await waitFor(() => expect(saveRecords).toHaveBeenCalledTimes(2));
    expect(saveProgress).toHaveBeenCalledTimes(1);
  });

  it('guards a record operation against double taps', async () => {
    let finish!: () => void;
    saveRecords.mockImplementationOnce(() => new Promise<undefined>((resolve) => {
      finish = () => resolve(undefined);
    }));
    const user = renderToday();
    renderPage();
    const button = await screen.findByRole('button', { name: '한입도전' });

    await user.dblClick(button);
    expect(saveRecords).toHaveBeenCalledTimes(1);
    finish();
    await waitFor(() => expect(reload).toHaveBeenCalledTimes(1));
  });
});

describe('today meal loading', () => {
  it('uses the exact Seoul calendar date', () => {
    expect(seoulDate(new Date('2026-07-23T15:00:00.000Z'))).toBe('20260724');
  });

  it('keeps a live result when device cache writing fails', async () => {
    const cacheMeal = vi.fn().mockRejectedValue(new Error('storage unavailable'));
    const result = await loadTodayMeal({
      mode: { kind: 'live' },
      profile: makeProfile(),
      client: { fetchMeal: vi.fn().mockResolvedValue(meal) } as never,
      repository: { cacheMeal } as unknown as AppRepository,
      now: new Date('2026-07-23T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'live', meal });
  });

  it('does not use cache when the upstream reports no meal', async () => {
    const { NeisClientError } = await import('../../services/neisClient');
    const getCachedMeal = vi.fn().mockResolvedValue({ meal, source: 'cache' });
    const result = await loadTodayMeal({
      mode: { kind: 'live' },
      profile: makeProfile(),
      client: {
        fetchMeal: vi.fn().mockRejectedValue(new NeisClientError('NO_DATA', 'no meal', 404)),
      } as never,
      repository: { getCachedMeal } as unknown as AppRepository,
    });

    expect(result).toEqual({ kind: 'noMeal' });
    expect(getCachedMeal).not.toHaveBeenCalled();
  });

  it('accepts cache only for the requested date after a live failure', async () => {
    const { NeisClientError } = await import('../../services/neisClient');
    const result = await loadTodayMeal({
      mode: { kind: 'live' },
      profile: makeProfile(),
      client: {
        fetchMeal: vi.fn().mockRejectedValue(new NeisClientError('UPSTREAM_ERROR', 'down', 503)),
      } as never,
      repository: {
        getCachedMeal: vi.fn().mockResolvedValue({ meal: { ...meal, date: '20260723' }, source: 'cache' }),
      } as unknown as AppRepository,
      now: new Date('2026-07-23T15:00:00.000Z'),
    });

    expect(result).toEqual({ kind: 'error', code: 'UPSTREAM_ERROR' });
  });

  it('suppresses stale loader errors after its client changes', async () => {
    const actual = await vi.importActual<typeof import('./useTodayMeal')>('./useTodayMeal');
    let rejectFirst!: (reason: unknown) => void;
    const first = new Promise<never>((_resolve, reject) => { rejectFirst = reject; });
    const firstClient = { fetchMeal: vi.fn().mockReturnValue(first) };
    const secondClient = { fetchMeal: vi.fn().mockResolvedValue(meal) };
    const repository = { cacheMeal: vi.fn().mockResolvedValue(undefined) } as unknown as AppRepository;

    function Probe({ client }: { client: typeof firstClient }) {
      const { result } = actual.useTodayMeal({
        mode: { kind: 'live' },
        profile: makeProfile(),
        client: client as never,
        repository,
      });
      return <output>{result === 'loading' ? 'loading' : result.kind}</output>;
    }

    const view = render(<Probe client={firstClient} />);
    await waitFor(() => expect(firstClient.fetchMeal).toHaveBeenCalled());
    view.rerender(<Probe client={secondClient as typeof firstClient} />);
    await waitFor(() => expect(screen.getByText('live')).toBeInTheDocument());
    rejectFirst(new Error('stale failure'));
    await new Promise((resolve) => window.setTimeout(resolve, 0));

    expect(screen.getByText('live')).toBeInTheDocument();
  });
});
