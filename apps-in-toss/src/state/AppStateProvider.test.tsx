import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { AppRepository } from '../services/repository';
import { AppStateProvider, useAppState } from './AppStateProvider';

function StateProbe() {
  const { state } = useAppState();
  return <p>{state.status === 'recoverableError' ? state.message : state.status}</p>;
}

describe('AppStateProvider', () => {
  it('loads the device-only repository during bootstrap', async () => {
    const repository = new AppRepository({
      getItem: vi.fn(async () => null),
      setItem: vi.fn(async () => undefined),
      removeItem: vi.fn(async () => undefined),
    });

    render(<AppStateProvider repository={repository}><StateProbe /></AppStateProvider>);

    expect(await screen.findByText('ready')).toBeInTheDocument();
  });

  it('shows a recoverable error when device storage cannot load', async () => {
    const repository = new AppRepository({
      getItem: vi.fn(async () => { throw new Error('storage unavailable'); }),
      setItem: vi.fn(async () => undefined),
      removeItem: vi.fn(async () => undefined),
    });

    render(<AppStateProvider repository={repository}><StateProbe /></AppStateProvider>);

    expect(await screen.findByText('저장된 정보를 불러오지 못했어요.')).toBeInTheDocument();
  });
});
