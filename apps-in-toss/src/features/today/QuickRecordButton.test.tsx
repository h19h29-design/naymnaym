import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TDSMobileAITProvider } from '@toss/tds-mobile-ait';
import { describe, expect, it, vi } from 'vitest';
import type { MealItem, MealStatus } from '../../domain/types';
import { QuickRecordButton } from './QuickRecordButton';

const items: MealItem[] = [
  { id: '1', name: '현미밥', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '현미밥' },
  { id: '2', name: '우유', allergyCodes: [2], nutrients: [], tags: [], sourceRawText: '우유(2)' },
  { id: '3', name: '사과', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '사과' },
];

function renderButton(recordMeal: (date: string, menuName: string, status: MealStatus) => Promise<void> = vi.fn(async () => undefined)) {
  render(<TDSMobileAITProvider brandPrimaryColor="#FF8A3D"><QuickRecordButton
    date="20260921" items={items} allergyCodes={[2]} recordMeal={recordMeal} onComplete={() => undefined}
  /></TDSMobileAITProvider>);
  return recordMeal;
}

describe('QuickRecordButton', () => {
  it('confirms the allergy count before recording every item in menu order', async () => {
    const recordMeal = renderButton();
    await userEvent.click(screen.getByRole('button', { name: '오늘 급식 전체를 한 번에 기록하기' }));
    expect(screen.getByText('알레르기 주의 메뉴 1개는 안 먹음으로 기록해요.')).toBeVisible();
    expect(recordMeal).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: '오늘 급식 전체 기록 확정' }));
    await waitFor(() => expect(recordMeal).toHaveBeenCalledTimes(3));
    expect(vi.mocked(recordMeal).mock.calls).toEqual([
      ['20260921', '현미밥', 'finished'], ['20260921', '우유', 'skipped'], ['20260921', '사과', 'finished'],
    ]);
  });

  it('disables confirmation while sequential recording is in progress', async () => {
    let finishFirst!: () => void;
    const recordMeal = vi.fn(() => new Promise<void>((resolve) => { finishFirst = resolve; }));
    renderButton(recordMeal);
    await userEvent.click(screen.getByRole('button', { name: '오늘 급식 전체를 한 번에 기록하기' }));
    const confirm = screen.getByRole('button', { name: '오늘 급식 전체 기록 확정' });
    await userEvent.click(confirm);
    expect(confirm).toBeDisabled();
    expect(recordMeal).toHaveBeenCalledTimes(1);
    finishFirst();
  });
});
