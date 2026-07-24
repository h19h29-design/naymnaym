import { StrictMode, useEffect, useState } from 'react';
import {
  act,
  cleanup,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Profile } from '../domain/types';
import { AppRepository } from '../services/repository';
import type { RepositoryState } from '../services/repository';
import { makeProfile } from '../test/fixtures';
import {
  AppStateProvider,
  useAppState,
} from './AppStateProvider';

afterEach(cleanup);

type Reload = ReturnType<typeof useAppState>['reload'];

function makeRepository() {
  return new AppRepository({
    getItem: vi.fn(async () => null),
    setItem: vi.fn(async () => undefined),
    removeItem: vi.fn(async () => undefined),
  });
}

function makeState(profile: Profile | null): RepositoryState {
  return {
    profile,
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

function StateProbe() {
  const { reload, state } = useAppState();
  return (
    <>
      <p>{state.status === 'recoverableError' ? state.message : state.status}</p>
      {state.status === 'ready' && (
        <p>{state.profile?.nickname ?? '프로필 없음'}</p>
      )}
      <button onClick={() => void reload()}>다시 불러오기</button>
    </>
  );
}

function ReloadCapture({
  capture,
}: {
  capture(reload: Reload): void;
}) {
  const { reload } = useAppState();
  useEffect(() => {
    capture(reload);
  }, [capture, reload]);
  return null;
}

function ReloadResultProbe() {
  const { reload } = useAppState();
  const [result, setResult] = useState<string | null>(null);

  return (
    <>
      <button onClick={() => void reload().then((ok) => setResult(String(ok)))}>
        결과와 함께 다시 불러오기
      </button>
      {result !== null ? <p>{result}</p> : null}
    </>
  );
}

describe('AppStateProvider', () => {
  it('loads the device-only repository during bootstrap', async () => {
    const repository = makeRepository();

    render(<AppStateProvider repository={repository}><StateProbe /></AppStateProvider>);

    expect(await screen.findByText('ready')).toBeInTheDocument();
  });

  it('shows a recoverable error when device storage cannot load', async () => {
    const repository = makeRepository();
    vi.spyOn(repository, 'load').mockRejectedValue(new Error('storage unavailable'));

    render(<AppStateProvider repository={repository}><StateProbe /></AppStateProvider>);

    expect(await screen.findByText('저장된 정보를 불러오지 못했어요.')).toBeInTheDocument();
  });

  it('returns false while retaining recoverable state when a manual reload fails', async () => {
    const repository = makeRepository();
    vi.spyOn(repository, 'load')
      .mockResolvedValueOnce(makeState(null))
      .mockRejectedValueOnce(new Error('storage unavailable'));

    render(
      <AppStateProvider repository={repository}>
        <ReloadResultProbe />
        <StateProbe />
      </AppStateProvider>,
    );
    expect(await screen.findByText('ready')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: '결과와 함께 다시 불러오기' }));

    expect(await screen.findByText('false')).toBeInTheDocument();
    expect(screen.getByText('저장된 정보를 불러오지 못했어요.')).toBeInTheDocument();
  });

  it('ignores an earlier StrictMode load that resolves after the active load', async () => {
    const first = deferred<RepositoryState>();
    const active = deferred<RepositoryState>();
    const repository = makeRepository();
    const load = vi.spyOn(repository, 'load')
      .mockImplementationOnce(() => first.promise)
      .mockImplementationOnce(() => active.promise);

    render(
      <StrictMode>
        <AppStateProvider repository={repository}><StateProbe /></AppStateProvider>
      </StrictMode>,
    );
    await waitFor(() => expect(load).toHaveBeenCalledTimes(2));

    active.resolve(makeState(makeProfile({ nickname: '최신 프로필' })));
    expect(await screen.findByText('최신 프로필')).toBeInTheDocument();

    await act(async () => {
      first.resolve(makeState(makeProfile({ nickname: '이전 프로필' })));
      await first.promise;
    });

    expect(screen.getByText('최신 프로필')).toBeInTheDocument();
    expect(screen.queryByText('이전 프로필')).not.toBeInTheDocument();
  });

  it('ignores a deferred completion and captured reload after unmount', async () => {
    const pending = deferred<RepositoryState>();
    const repository = makeRepository();
    const load = vi.spyOn(repository, 'load')
      .mockImplementationOnce(() => pending.promise);
    let capturedReload: Reload | undefined;
    const capture = (reload: Reload) => {
      capturedReload = reload;
    };
    const view = render(
      <AppStateProvider repository={repository}>
        <ReloadCapture capture={capture} />
      </AppStateProvider>,
    );
    await waitFor(() => expect(load).toHaveBeenCalledTimes(1));
    expect(capturedReload).toBeDefined();

    view.unmount();
    await act(async () => {
      pending.resolve(makeState(makeProfile()));
      await pending.promise;
    });
    expect(await capturedReload!()).toBe(false);

    expect(load).toHaveBeenCalledTimes(1);
  });

  it('keeps reload referentially stable while the repository is unchanged', async () => {
    const repository = makeRepository();
    const reloads: Reload[] = [];
    const capture = (reload: Reload) => {
      reloads.push(reload);
    };
    render(
      <AppStateProvider repository={repository}>
        <ReloadCapture capture={capture} />
        <StateProbe />
      </AppStateProvider>,
    );

    expect(await screen.findByText('ready')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: '다시 불러오기' }));
    expect(await screen.findByText('ready')).toBeInTheDocument();

    expect(new Set(reloads)).toHaveLength(1);
  });
});
