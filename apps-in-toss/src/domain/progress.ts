import type { EatingStatus, MealRecord, XpAward, XpInput } from './types';

const BASE_XP: Record<EatingStatus, number> = {
  finished: 10,
  half: 12,
  oneBite: 18,
  smelledOnly: 10,
  difficultToday: 3,
  allergyAvoided: 8,
};

const RETRY_XP: Record<EatingStatus, number> = {
  difficultToday: 5,
  smelledOnly: 10,
  oneBite: 25,
  half: 35,
  finished: 35,
  allergyAvoided: 0,
};

const LEVELS = [
  [0, '냠냠 새싹'],
  [80, '한 입 탐험가'],
  [180, '냠냠 용사'],
  [320, '편식 몬스터 사냥꾼'],
  [500, '급식 히어로'],
  [720, '영양 마스터'],
  [1000, '레전드 냠냠러'],
] as const;

export function calculateXp(input: XpInput): XpAward {
  const combinedBefore = input.baseEarnedToday + input.challengeEarnedToday;
  const combinedRoom = Math.max(0, 100 - combinedBefore);
  const base = Math.min(
    BASE_XP[input.status],
    Math.max(0, 50 - input.baseEarnedToday),
    combinedRoom,
  );
  const challengePotential =
    (input.previousStatus === 'difficultToday' ? RETRY_XP[input.status] : 0) +
    (input.variedFoodGroup ? 5 : 0) +
    (input.streakRecord ? 5 : 0) +
    (input.allergySafetyCheck ? 10 : 0);
  const challenge = Math.min(
    challengePotential,
    Math.max(0, 70 - input.challengeEarnedToday),
    Math.max(0, combinedRoom - base),
  );
  return { base, challenge, total: base + challenge };
}

export function levelFor(totalXp: number): {
  number: number;
  threshold: number;
  title: string;
} {
  let index = 0;
  LEVELS.forEach(([threshold], candidate) => {
    if (totalXp >= threshold) index = candidate;
  });
  const [threshold, title] = LEVELS[index];
  return { number: index + 1, threshold, title };
}

export function hasPreviousDayRecord(records: MealRecord[], date: string): boolean {
  const current = new Date(Date.UTC(
    Number(date.slice(0, 4)),
    Number(date.slice(4, 6)) - 1,
    Number(date.slice(6, 8)),
  ));
  current.setUTCDate(current.getUTCDate() - 1);
  const previousDate = [
    current.getUTCFullYear(),
    String(current.getUTCMonth() + 1).padStart(2, '0'),
    String(current.getUTCDate()).padStart(2, '0'),
  ].join('');
  return records.some((record) => record.date === previousDate);
}
