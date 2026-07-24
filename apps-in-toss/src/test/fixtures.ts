import type { MealDay, School } from '@nyam/neis-contract';
import type { MealRecord, Profile } from '../domain/types';

export const school: School = {
  name: '가람중학교',
  officeCode: 'B10',
  schoolCode: '7011234',
  region: '서울특별시',
  address: '서울특별시 중구 테스트로 1',
  schoolType: 'middle',
};

export const meal: MealDay = {
  date: '20260724',
  menuItems: [{
    id: 'meal-1',
    name: '현미밥',
    allergyCodes: [],
    nutrients: ['탄수화물'],
    tags: [],
    sourceRawText: '현미밥',
  }],
  calorie: '812.3 Kcal',
  nutrition: '탄수화물(g) : 112.0',
  isSample: false,
  notice: null,
};

export function mealWithAllergen(code: number): MealDay {
  return {
    ...meal,
    menuItems: [{
      ...meal.menuItems[0],
      id: `allergen-${code}`,
      name: '알레르기 확인 메뉴',
      allergyCodes: [code],
    }],
  };
}

export function makeProfile(overrides: Partial<Profile> = {}): Profile {
  return {
    nickname: '냠냠이',
    schoolType: 'middle',
    school,
    allergyCodes: [],
    createdAt: '2026-07-24T00:00:00.000Z',
    ...overrides,
  };
}

export function makeRecord(overrides: Partial<MealRecord> = {}): MealRecord {
  return {
    date: '20260724',
    mealItemId: 'meal-1',
    mealName: '현미밥',
    status: 'oneBite',
    difficultyReason: null,
    awardedXp: 18,
    recordedAt: '2026-07-24T03:00:00.000Z',
    ...overrides,
  };
}
