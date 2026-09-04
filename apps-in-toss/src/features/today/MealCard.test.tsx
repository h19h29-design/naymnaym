import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { MealCard } from './MealCard';

describe('MealCard', () => {
  it('locks one-bite for an allergy-risk item with the required safety message', async () => {
    const onStatus = vi.fn();
    render(<MealCard item={{ id: '1', name: '우유', allergyCodes: [2], nutrients: [], tags: [], sourceRawText: '우유(2)' }} risky onStatus={onStatus} />);
    expect(screen.getByText('알레르기 가능성이 있어요. 학교 안내와 보호자 확인이 먼저예요.')).toBeVisible();
    expect(screen.getByRole('button', { name: '우유 한 입 도전' })).toBeDisabled();
    await userEvent.click(screen.getByRole('button', { name: '우유 잘 먹음' }));
    expect(onStatus).toHaveBeenCalledWith('finished');
  });
});
