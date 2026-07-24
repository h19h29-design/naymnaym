import type { MealDay } from '@nyam/neis-contract';

export const demoMeal = {
  date: '20260724',
  menuItems: [
    {
      id: 'demo-1',
      name: '현미밥',
      allergyCodes: [],
      nutrients: ['탄수화물'],
      tags: ['체험'],
      sourceRawText: '현미밥',
    },
    {
      id: 'demo-2',
      name: '닭갈비',
      allergyCodes: [5, 6, 15],
      nutrients: ['단백질', '철분'],
      tags: ['체험'],
      sourceRawText: '닭갈비(5.6.15.)',
    },
  ],
  calorie: '체험 데이터',
  nutrition: null,
  isSample: true,
  notice: '체험 급식은 실제 학교 급식이 아니며 기록과 XP가 저장되지 않아요.',
} satisfies MealDay;
