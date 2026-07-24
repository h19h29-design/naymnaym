import type { RepositoryState } from '../services/repository';

export type AppState =
  | { status: 'loading' }
  | ({ status: 'ready' } & RepositoryState)
  | { status: 'recoverableError'; message: string };

export type AppAction =
  | { type: 'loaded'; value: RepositoryState }
  | { type: 'failed'; message: string }
  | { type: 'reset' };

export function reducer(_state: AppState, action: AppAction): AppState {
  if (action.type === 'loaded') return { status: 'ready', ...action.value };
  if (action.type === 'failed') {
    return { status: 'recoverableError', message: action.message };
  }
  return { status: 'loading' };
}
