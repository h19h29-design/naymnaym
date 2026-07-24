import { describe, expect, it } from 'vitest';
import { makeProfile } from '../test/fixtures';
import { reducer } from './reducer';

describe('reducer', () => {
  it('enters ready state with the complete repository snapshot', () => {
    const value = {
      profile: makeProfile(),
      progress: {
        totalXp: 0,
        baseEarnedByDate: {},
        challengeEarnedByDate: {},
      },
      mealRecords: [],
      challengeRecords: [],
    };

    expect(reducer({ status: 'loading' }, { type: 'loaded', value }))
      .toEqual({ status: 'ready', ...value });
  });

  it('returns to loading when reset after a recoverable error', () => {
    expect(reducer(
      { status: 'recoverableError', message: '저장된 정보를 불러오지 못했어요.' },
      { type: 'reset' },
    )).toEqual({ status: 'loading' });
  });
});
