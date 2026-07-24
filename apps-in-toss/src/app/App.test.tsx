import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import type { Profile } from '../domain/types';
import { makeProfile } from '../test/fixtures';
import { routeObjects } from './routes';

afterEach(cleanup);

function renderTestApp({
  initialEntry,
  profile,
}: {
  initialEntry: string;
  profile: Profile | null;
}) {
  const router = createMemoryRouter(routeObjects(profile), {
    initialEntries: [initialEntry],
  });
  return render(<RouterProvider router={router} />);
}

describe('direct routes', () => {
  it('redirects a first-time /today deep link to onboarding', async () => {
    renderTestApp({ initialEntry: '/today', profile: null });

    expect(await screen.findByRole('heading', { name: '냠냠레벨업 시작하기' }))
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

    expect(await screen.findByRole('heading', { name: '냠냠레벨업 시작하기' }))
      .toBeInTheDocument();
  });

  it('routes an unconfigured settings deep link to onboarding', async () => {
    renderTestApp({ initialEntry: '/settings', profile: null });

    expect(await screen.findByRole('heading', { name: '냠냠레벨업 시작하기' }))
      .toBeInTheDocument();
  });
});
