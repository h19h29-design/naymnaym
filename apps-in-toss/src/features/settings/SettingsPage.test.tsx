import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { AppProviders } from '../../app/AppProviders';
import { routeObjects } from '../../app/routes';
import type { Profile } from '../../domain/types';
import type { AppRepository, RepositoryState } from '../../services/repository';
import { AppStateProvider } from '../../state/AppStateProvider';
import { makeProfile } from '../../test/fixtures';

const { openURL } = vi.hoisted(() => ({ openURL: vi.fn() }));

vi.mock('@apps-in-toss/web-framework', () => ({ openURL }));

const emptyState = (): RepositoryState => ({
  profile: null,
  progress: { totalXp: 0, baseEarnedByDate: {}, challengeEarnedByDate: {} },
  mealRecords: [],
  challengeRecords: [],
});

function renderSettings({
  profile = makeProfile(),
  deleteAll = vi.fn(async () => undefined),
  initialEntries = ['/settings'],
  initialIndex,
}: {
  profile?: Profile;
  deleteAll?: AppRepository['deleteAll'];
  initialEntries?: string[];
  initialIndex?: number;
} = {}) {
  const router = createMemoryRouter(routeObjects(), { initialEntries, initialIndex });
  const repository = {
    load: vi.fn(async () => ({ ...emptyState(), profile })),
    deleteAll,
  } as unknown as AppRepository;

  render(
    <AppProviders>
      <AppStateProvider repository={repository}>
        <RouterProvider router={router} />
      </AppStateProvider>
    </AppProviders>,
  );

  return { user: userEvent.setup(), router, deleteAll };
}

let nativeInsertAdjacentElement: typeof HTMLElement.prototype.insertAdjacentElement;

describe('SettingsPage', () => {
  beforeAll(() => {
    nativeInsertAdjacentElement = HTMLElement.prototype.insertAdjacentElement;
    HTMLElement.prototype.insertAdjacentElement = function (position, element) {
      const valid = position === 'beforebegin' || position === 'afterbegin'
        || position === 'beforeend' || position === 'afterend';
      const tdsFocusGuard = this === document.body
        && !valid
        && element instanceof HTMLElement
        && element.hasAttribute('data-radix-focus-guard');
      return nativeInsertAdjacentElement.call(this, tdsFocusGuard ? 'afterbegin' : position, element);
    };
  });

  afterAll(() => {
    HTMLElement.prototype.insertAdjacentElement = nativeInsertAdjacentElement;
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('requires confirmation and returns to onboarding after local deletion', async () => {
    const { user, deleteAll, router } = renderSettings();

    await user.click(await screen.findByRole('button', { name: '내 데이터 삭제' }));
    expect(screen.getByText('이 기기의 프로필, 기록, XP가 모두 삭제돼요.')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /모두 삭제/ }));

    expect(deleteAll).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));
  });

  it('keeps back navigation on onboarding after successful deletion', async () => {
    const { user, router } = renderSettings({
      initialEntries: ['/today', '/settings'],
      initialIndex: 1,
    });

    await user.click(await screen.findByRole('button', { name: '내 데이터 삭제' }));
    await user.click(screen.getByRole('button', { name: /모두 삭제/ }));
    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));

    await router.navigate(-1);
    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));
    expect(screen.queryByRole('heading', { name: '오늘 급식' })).not.toBeInTheDocument();
  });

  it('guards double taps and disables deletion controls while pending', async () => {
    let resolve!: () => void;
    const deleteAll = vi.fn(() => new Promise<void>((done) => { resolve = done; }));
    const { user, router } = renderSettings({ deleteAll });

    await user.click(await screen.findByRole('button', { name: '내 데이터 삭제' }));
    const confirm = screen.getByRole('button', { name: '모두 삭제' });
    await user.dblClick(confirm);

    expect(deleteAll).toHaveBeenCalledTimes(1);
    expect(confirm).toBeDisabled();
    expect(screen.getByRole('button', { name: '내 데이터 삭제' })).toBeDisabled();
    resolve();
    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));
  });

  it('preserves the active state after a deletion failure and permits retry', async () => {
    const deleteAll = vi.fn()
      .mockRejectedValueOnce(new Error('write failed'))
      .mockResolvedValueOnce(undefined);
    const { user, router } = renderSettings({ deleteAll });

    await user.click(await screen.findByRole('button', { name: '내 데이터 삭제' }));
    await user.click(screen.getByRole('button', { name: '모두 삭제' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      '데이터를 삭제하지 못했어요. 다시 시도해 주세요.',
    );
    expect(screen.getByText('설정', { selector: 'h1' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /모두 삭제/ }));
    expect(deleteAll).toHaveBeenCalledTimes(2);
    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));
  });

  it('opens only approved HTTPS policy destinations', async () => {
    const { user } = renderSettings();

    await user.click(await screen.findByRole('button', { name: '개인정보 처리방침' }));
    expect(openURL).toHaveBeenCalledWith(
      'https://h19h29-design.github.io/naymnaym/privacy.html',
    );
    await user.click(screen.getByRole('button', { name: '문의 및 지원' }));
    expect(openURL).toHaveBeenLastCalledWith(
      'https://h19h29-design.github.io/naymnaym/support.html',
    );
  });

  it('announces a safe error when an approved external link fails to open', async () => {
    openURL.mockRejectedValueOnce(new Error('not available'));
    const { user } = renderSettings();

    await user.click(await screen.findByRole('button', { name: '개인정보 처리방침' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '링크를 열지 못했어요. 다시 시도해 주세요.',
    );
    await user.click(screen.getByRole('button', { name: '개인정보 처리방침' }));
    expect(openURL).toHaveBeenCalledTimes(2);
  });

  it('guards repeated policy taps while opening and allows a later retry', async () => {
    let resolve!: () => void;
    openURL.mockImplementationOnce(() => new Promise<void>((done) => { resolve = done; }));
    const { user } = renderSettings();
    const privacy = await screen.findByRole('button', { name: '개인정보 처리방침' });

    await user.dblClick(privacy);
    expect(openURL).toHaveBeenCalledTimes(1);
    expect(privacy).toBeDisabled();
    expect(screen.getByRole('button', { name: '문의 및 지원' })).toBeDisabled();
    resolve();
    await waitFor(() => expect(privacy).not.toBeDisabled());

    await user.click(privacy);
    expect(openURL).toHaveBeenCalledTimes(2);
  });

  it('navigates to edit onboarding with the settings return path', async () => {
    const { user, router } = renderSettings();

    await user.click(await screen.findByRole('button', { name: '프로필과 알레르기 수정' }));

    await waitFor(() => expect(router.state.location.pathname).toBe('/onboarding'));
    expect(router.state.location.search).toBe('?mode=edit&next=%2Fsettings');
  });
});
