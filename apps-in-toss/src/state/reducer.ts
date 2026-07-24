import type { RepositoryState } from '../services/repository';

export type AppState =
  | { status: 'loading' }
  | ({ status: 'ready' } & RepositoryState)
  | { status: 'recoverableError'; message: string };

export type AppAction =
  | { type: 'loaded'; value: RepositoryState }
  | { type: 'failed'; message: string }
  | { type: 'reset' }
  | { type: 'cleared' };

export function reducer(_state: AppState, action: AppAction): AppState {
  if (action.type === 'loaded') return { status: 'ready', ...action.value };
  if (action.type === 'failed') {
    return { status: 'recoverableError', message: action.message };
  }
  if (action.type === 'cleared') {
    return {
      status: 'ready',
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
  return { status: 'loading' };
}
