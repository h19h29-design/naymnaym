import type { MealDay } from '../../domain/types';

export function demoMeal(date: string): MealDay {
  return {
    date,
    isSample: true,
    notice: '체험 급식은 기기에 저장되지 않아요.',
    calorie: '체험용', nutrition: null,
    menuItems: [
      { id: 'demo-1', name: '귀리밥', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '귀리밥' },
      { id: 'demo-2', name: '두부채소국', allergyCodes: [5, 6], nutrients: [], tags: [], sourceRawText: '두부채소국(5.6)' },
      { id: 'demo-3', name: '사과', allergyCodes: [], nutrients: [], tags: [], sourceRawText: '사과' },
    ],
  };
}
