import { act, renderHook, waitFor } from '@testing-library/react';
import { type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { AppStateProvider, useAppState } from './AppStateProvider';
import { EMPTY_STATE } from '../services/repository';

describe('AppStateProvider', () => {
  it('persists one replacement record and recomputed total XP', async () => {
    const repository = { load: vi.fn(async () => EMPTY_STATE), save: vi.fn(async () => {}), clearAllConfirmed: vi.fn(async () => {}) };
    const client = { searchSchools: vi.fn(), fetchMeals: vi.fn(), fetchMealsRange: vi.fn() };
    const wrapper = ({ children }: { children: ReactNode }) => <AppStateProvider repository={repository} client={client as never}>{children}</AppStateProvider>;
    const { result } = renderHook(() => useAppState(), { wrapper });
    await waitFor(() => expect(result.current.ready).toBe(true));
    await act(async () => { await result.current.recordMeal('20260904', '밥', 'oneBite'); });
    await act(async () => { await result.current.recordMeal('20260904', ' 밥 ', 'finished'); });
    expect(result.current.state.mealRecords).toHaveLength(1);
    expect(result.current.state.totalXP).toBe(10);
    expect(repository.save).toHaveBeenLastCalledWith(expect.objectContaining({ totalXP: 10 }));
  });
});
