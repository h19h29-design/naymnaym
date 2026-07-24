import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { AppProviders } from '../../app/AppProviders';
import { routeObjects } from '../../app/routes';
import { makeProfile, meal } from '../../test/fixtures';
import { AppRepository } from '../../services/repository';
import type { KeyValueStorage } from '../../services/storage';
import { AppStateProvider } from '../../state/AppStateProvider';
import { neisClient } from '../../services/neisClient';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function repositoryWithProfile() {
  const values = new Map<string, string>([
    ['nyam-toss:profile:v1', JSON.stringify(makeProfile())],
  ]);
  const storage: KeyValueStorage = {
    getItem: async (key) => values.get(key) ?? null,
    setItem: async (key, value) => { values.set(key, value); },
    removeItem: async (key) => { values.delete(key); },
  };
  return new AppRepository(storage);
}

describe('TodayPage with AppStateProvider', () => {
  it('keeps the today page and its retry error mounted when post-save reload fails', async () => {
    const repository = repositoryWithProfile();
    const initial = await repository.load();
    vi.spyOn(repository, 'load')
      .mockResolvedValueOnce(initial)
      .mockRejectedValueOnce(new Error('reload failed'));
    vi.spyOn(neisClient, 'fetchMeal').mockImplementation(async (_school, date) => ({ ...meal, date }));
    const router = createMemoryRouter(routeObjects(), { initialEntries: ['/today'] });

    render(
      <AppProviders>
        <AppStateProvider repository={repository}>
          <RouterProvider router={router} />
        </AppStateProvider>
      </AppProviders>,
    );
    const user = userEvent.setup();
    await user.click(await screen.findByRole('button', { name: '한입도전' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('기록을 저장하지 못했어요. 다시 시도해 주세요.');
    expect(screen.getByRole('heading', { name: '오늘 급식' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/today');
    await user.click(screen.getByRole('button', { name: '다시 시도' }));
    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument());
  });
});
