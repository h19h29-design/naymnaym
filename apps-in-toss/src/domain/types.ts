import type { School } from '@nyam/neis-contract';

export type EatingStatus =
  | 'finished'
  | 'half'
  | 'oneBite'
  | 'smelledOnly'
  | 'difficultToday'
  | 'allergyAvoided';

export type DifficultyReason =
  | 'texture'
  | 'smell'
  | 'spicy'
  | 'color'
  | 'newFood'
  | 'allergy'
  | 'other';

export interface Profile {
  nickname: string;
  schoolType: 'middle' | 'high';
  school: School;
  allergyCodes: number[];
  createdAt: string;
}

export interface MealRecord {
  date: string;
  mealItemId: string;
  mealName: string;
  status: EatingStatus;
  difficultyReason: DifficultyReason | null;
  awardedXp: number;
  recordedAt: string;
}

export interface Progress {
  totalXp: number;
  baseEarnedByDate: Record<string, number>;
  challengeEarnedByDate: Record<string, number>;
}

export interface ChallengeRecord {
  date: string;
  mealItemId: string;
  kinds: Array<
    'variedFoodGroup' | 'streakRecord' | 'allergySafetyCheck' | 'retry'
  >;
  awardedXp: number;
}

export interface XpInput {
  status: EatingStatus;
  previousStatus: EatingStatus | null;
  baseEarnedToday: number;
  challengeEarnedToday: number;
  variedFoodGroup: boolean;
  streakRecord: boolean;
  allergySafetyCheck: boolean;
}

export interface XpAward {
  base: number;
  challenge: number;
  total: number;
}

export type SessionMode = { kind: 'live' } | { kind: 'demo' };
