import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { levelFor } from '../../domain/progress';
import { meal, mealWithAllergen } from '../../test/fixtures';
import { NoMealState } from './NoMealState';

describe('NoMealState', () => {
  afterEach(cleanup);

  it('shows the grown character and safe next meal preview', async () => {
    const handlers = {
      onRetryToday: vi.fn(),
      onRetryNext: vi.fn(),
      onOpenWeekly: vi.fn(),
      onEditSchool: vi.fn(),
    };
    const user = userEvent.setup();

    render(
      <NoMealState
        level={levelFor(150)}
        totalXp={150}
        allergyCodes={[6]}
        nextMeal={{ kind: 'live', meal: mealWithAllergen(6) }}
        {...handlers}
      />,
    );

    expect(screen.getByRole('img', { name: /레벨 2/ })).toBeInTheDocument();
    expect(screen.getByText('오늘은 급식이 없는 날이에요')).toBeInTheDocument();
    expect(screen.getByText('다음 급식')).toBeInTheDocument();
    expect(screen.getByText('알레르기 안전을 먼저 확인해 주세요 · 밀')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: '주간 급식표 보기' }));
    expect(handlers.onOpenWeekly).toHaveBeenCalledOnce();
  });

  it('announces that the next meal is loading', () => {
    render(
      <NoMealState
        level={levelFor(0)}
        totalXp={0}
        allergyCodes={[]}
        nextMeal={{ kind: 'loading' }}
        onRetryToday={vi.fn()}
        onRetryNext={vi.fn()}
        onOpenWeekly={vi.fn()}
        onEditSchool={vi.fn()}
      />,
    );

    expect(screen.getByRole('status')).toHaveTextContent('다음 급식을 확인하고 있어요');
  });

  it('labels cached next meal details without offering meal recording', () => {
    render(
      <NoMealState
        level={levelFor(80)}
        totalXp={80}
        allergyCodes={[]}
        nextMeal={{ kind: 'cache', meal }}
        onRetryToday={vi.fn()}
        onRetryNext={vi.fn()}
        onOpenWeekly={vi.fn()}
        onEditSchool={vi.fn()}
      />,
    );

    expect(screen.getByRole('status')).toHaveTextContent('저장된 다음 급식');
    expect(screen.getByText('7월 24일 금요일')).toBeInTheDocument();
    expect(screen.getByText('812.3 Kcal')).toBeInTheDocument();
    expect(screen.getByText('현미밥')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '오늘 급식 기록하기' })).not.toBeInTheDocument();
  });

  it('offers school settings when no next meal can be found', () => {
    render(
      <NoMealState
        level={levelFor(0)}
        totalXp={0}
        allergyCodes={[]}
        nextMeal={{ kind: 'notFound' }}
        onRetryToday={vi.fn()}
        onRetryNext={vi.fn()}
        onOpenWeekly={vi.fn()}
        onEditSchool={vi.fn()}
      />,
    );

    expect(screen.getByRole('status')).toHaveTextContent('다음 급식을 찾지 못했어요');
    expect(screen.getByRole('button', { name: '학교 설정 확인' })).toBeInTheDocument();
  });

  it('alerts on next meal errors and retries only the next meal', async () => {
    const onRetryNext = vi.fn();
    const user = userEvent.setup();

    render(
      <NoMealState
        level={levelFor(0)}
        totalXp={0}
        allergyCodes={[]}
        nextMeal={{ kind: 'error', code: 'UPSTREAM_ERROR' }}
        onRetryToday={vi.fn()}
        onRetryNext={onRetryNext}
        onOpenWeekly={vi.fn()}
        onEditSchool={vi.fn()}
      />,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('다음 급식을 불러오지 못했어요');
    await user.click(screen.getByRole('button', { name: '다음 급식 다시 시도' }));
    expect(onRetryNext).toHaveBeenCalledOnce();
    expect(screen.queryByRole('button', { name: '오늘 급식 기록하기' })).not.toBeInTheDocument();
  });

  it.each([
    { kind: 'idle' as const },
    { kind: 'loading' as const },
    { kind: 'live' as const, meal },
    { kind: 'cache' as const, meal },
    { kind: 'notFound' as const },
    { kind: 'error' as const, code: 'UPSTREAM_ERROR' },
  ])('does not offer meal recording for a $kind next-meal result', (nextMeal) => {
    render(
      <NoMealState
        level={levelFor(0)}
        totalXp={0}
        allergyCodes={[]}
        nextMeal={nextMeal}
        onRetryToday={vi.fn()}
        onRetryNext={vi.fn()}
        onOpenWeekly={vi.fn()}
        onEditSchool={vi.fn()}
      />,
    );

    expect(screen.queryByRole('button', { name: '오늘 급식 기록하기' })).not.toBeInTheDocument();
  });
});
