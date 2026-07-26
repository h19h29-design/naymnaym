import {
  createMemoryRouter,
  RouterProvider,
  useNavigate,
} from 'react-router-dom';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it } from 'vitest';
import type { Profile } from '../domain/types';
import { AppRepository } from '../services/repository';
import type { KeyValueStorage } from '../services/storage';
import { AppStateProvider, useAppState } from '../state/AppStateProvider';
import { makeProfile } from '../test/fixtures';
import { AppProviders } from './AppProviders';
import { routeObjects } from './routes';

afterEach(cleanup);

function makeRepository(profile: Profile | null) {
  const values = new Map<string, string>();
  if (profile !== null) {
    values.set('nyam-toss:profile:v1', JSON.stringify(profile));
  }
  const storage: KeyValueStorage = {
    getItem: async (key) => values.get(key) ?? null,
    setItem: async (key, value) => { values.set(key, value); },
    removeItem: async (key) => { values.delete(key); },
  };
  return new AppRepository(storage);
}

function renderTestApp({
  initialEntry,
  profile,
}: {
  initialEntry: string;
  profile: Profile | null;
}) {
  const router = createMemoryRouter(routeObjects(), {
    initialEntries: [initialEntry],
  });
  return render(
    <AppProviders>
      <AppStateProvider repository={makeRepository(profile)}>
        <RouterProvider router={router} />
      </AppStateProvider>
    </AppProviders>,
  );
}

function SaveProfileThenNavigate() {
  const { reload, repository, state } = useAppState();
  const navigate = useNavigate();

  const saveAndNavigate = async () => {
    await repository.saveProfile(makeProfile());
    await reload();
    navigate('/today');
  };

  if (state.status === 'loading') return <p>불러오는 중...</p>;
  if (state.status === 'recoverableError') return <p>{state.message}</p>;

  return <button onClick={() => void saveAndNavigate()}>프로필 저장 후 오늘로</button>;
}

describe('direct routes', () => {
  it('redirects a first-time /today deep link to onboarding', async () => {
    renderTestApp({ initialEntry: '/today', profile: null });

    expect(await screen.findByRole('heading', { name: '급식레벨업 시작하기' }))
      .toBeInTheDocument();
  });

  it('opens /today directly for a configured user', async () => {
    renderTestApp({ initialEntry: '/today', profile: makeProfile() });

    expect(await screen.findByRole('heading', { name: '오늘 급식' }))
      .toBeInTheDocument();
  });

  it('allows the explicitly requested demo route without a profile', async () => {
    renderTestApp({ initialEntry: '/today?demo=1', profile: null });

    expect(await screen.findByRole('heading', { name: '오늘 급식' }))
      .toBeInTheDocument();
  });

  it('does not treat other query values as demo mode', async () => {
    renderTestApp({ initialEntry: '/today?demo=true', profile: null });

    expect(await screen.findByRole('heading', { name: '급식레벨업 시작하기' }))
      .toBeInTheDocument();
  });

  it('routes an unconfigured settings deep link to onboarding', async () => {
    renderTestApp({ initialEntry: '/settings', profile: null });

    expect(await screen.findByRole('heading', { name: '급식레벨업 시작하기' }))
      .toBeInTheDocument();
  });

  it('recovers an unknown route to today for a configured user', async () => {
    renderTestApp({ initialEntry: '/unknown-route', profile: makeProfile() });

    expect(await screen.findByRole('heading', { name: '오늘 급식' })).toBeInTheDocument();
  });

  it('recovers an unknown route to onboarding for a new user', async () => {
    renderTestApp({ initialEntry: '/unknown-route', profile: null });

    expect(await screen.findByRole('heading', { name: '급식레벨업 시작하기' }))
      .toBeInTheDocument();
  });

  it('keeps navigation valid after onboarding saves a profile and reloads state', async () => {
    const user = userEvent.setup();
    const repository = makeRepository(null);
    const router = createMemoryRouter([
      ...routeObjects(),
      { path: '/test-onboarding-save', element: <SaveProfileThenNavigate /> },
    ], {
      initialEntries: ['/test-onboarding-save'],
    });
    render(
      <AppProviders>
        <AppStateProvider repository={repository}>
          <RouterProvider router={router} />
        </AppStateProvider>
      </AppProviders>,
    );

    await user.click(await screen.findByRole('button', { name: '프로필 저장 후 오늘로' }));

    expect(await screen.findByRole('heading', { name: '오늘 급식' }))
      .toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/today');
  });
});
