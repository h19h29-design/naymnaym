import type { MealRecord, MealStatus } from './types';

export const LEVELS = [
  [0, '냠냠 새싹'], [80, '한 입 탐험가'], [180, '냠냠 용사'], [320, '편식 몬스터 사냥꾼'],
  [500, '급식 히어로'], [720, '영양 마스터'], [1000, '레전드 냠냠러'], [1300, '별빛 셰프'],
  [1650, '균형 수호자'], [2050, '숲의 영양 기사'], [2500, '황금 한입 챔피언'], [3000, '전설의 급식대장'],
].map(([threshold, title], index) => ({ level: index + 1, threshold: threshold as number, title: title as string }));

const STATUS_XP: Record<MealStatus, number> = { skipped: 3, oneBite: 18, finished: 10 };
const DAILY_CAP = 50;

export function normalizeMenuName(value: string) {
  return value.trim().replace(/\s+/g, ' ').normalize('NFC');
}

export function recordIdentity(date: string, menuName: string) {
  return `${date}|${normalizeMenuName(menuName)}`;
}

function recompute(records: MealRecord[]) {
  const spent = new Map<string, number>();
  return [...records]
    .sort((a, b) => a.recordedAt - b.recordedAt || a.identity.localeCompare(b.identity))
    .map((record) => {
      const used = spent.get(record.date) ?? 0;
      const available = Math.max(0, DAILY_CAP - used);
      const xp = record.legacy ? record.xp : Math.min(STATUS_XP[record.status], available);
      spent.set(record.date, used + Math.min(xp, available));
      return { ...record, xp };
    });
}

export function applyMealStatus(records: MealRecord[], input: Omit<MealRecord, 'identity' | 'xp'>) {
  const menuName = normalizeMenuName(input.menuName);
  const identity = recordIdentity(input.date, menuName);
  const existing = records.find((record) => record.identity === identity);
  return recompute([
    ...records.filter((record) => record.identity !== identity),
    { ...input, menuName, identity, xp: 0, legacy: false, recordedAt: existing?.recordedAt ?? input.recordedAt },
  ]);
}

export function getLevel(totalXP: number) {
  return [...LEVELS].reverse().find((level) => totalXP >= level.threshold) ?? LEVELS[0];
}

export function getNextLevel(totalXP: number) {
  return LEVELS.find((level) => totalXP < level.threshold) ?? null;
}
