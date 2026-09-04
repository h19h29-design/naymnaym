import type { MealDay, MealItem, School, SchoolType } from '@nyam/neis-contract';

export type { MealDay, MealItem, School, SchoolType };

export type MealStatus = 'skipped' | 'oneBite' | 'finished';

export interface Profile {
  nickname: string;
  school: School;
  allergyCodes: number[];
}

export interface MealRecord {
  identity: string;
  date: string;
  menuName: string;
  status: MealStatus;
  xp: number;
  recordedAt: number;
  legacy?: boolean;
}

export interface MealCache {
  key: string;
  meal: MealDay;
  savedAt: number;
}

export interface AppState {
  schemaVersion: 2;
  profile: Profile | null;
  mealRecords: MealRecord[];
  totalXP: number;
  xpBaseline: number;
  cache: MealCache | null;
  cacheSavedAt: number | null;
}
