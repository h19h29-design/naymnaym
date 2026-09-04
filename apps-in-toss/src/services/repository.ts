import type { AppState, MealRecord, MealStatus, Profile } from '../domain/types';
import { normalizeMenuName, recordIdentity } from '../domain/progress';
import type { StoragePort } from './storage';

export const STATE_KEY = 'nyam-toss:state:v2';
export const LEGACY_KEYS = {
  profile: 'nyam-toss:profile:v1',
  progress: 'nyam-toss:progress:v1',
  records: 'nyam-toss:meal-records:v1',
  challenges: 'nyam-toss:challenge-records:v1',
  cache: 'nyam-toss:meal-cache:v1',
} as const;

export const EMPTY_STATE: AppState = {
  schemaVersion: 2,
  profile: null,
  mealRecords: [],
  totalXP: 0,
  xpBaseline: 0,
  cache: null,
  cacheSavedAt: null,
};

function parse(raw: string | null): unknown {
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

function object(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function numberList(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is number => Number.isInteger(item) && item >= 1 && item <= 19) : [];
}

function profileFrom(value: unknown): Profile | null {
  const source = object(value);
  const school = object(source?.school);
  const schoolType = school?.schoolType;
  if (!source || !school || !['elementary', 'middle', 'high'].includes(String(schoolType))) return null;
  const fields = ['name', 'officeCode', 'schoolCode', 'region', 'address'] as const;
  if (!fields.every((field) => typeof school[field] === 'string')) return null;
  return {
    nickname: typeof source.nickname === 'string' && source.nickname.trim() ? source.nickname.trim() : '냠냠이',
    school: {
      name: school.name as string, officeCode: school.officeCode as string, schoolCode: school.schoolCode as string,
      region: school.region as string, address: school.address as string,
      schoolType: schoolType as Profile['school']['schoolType'],
    },
    allergyCodes: numberList(source.allergyCodes),
  };
}

const OLD_ACTIONS: Record<string, MealStatus> = {
  difficultToday: 'skipped', smelledOnly: 'skipped', allergyAvoided: 'skipped', oneBite: 'oneBite', half: 'oneBite', finished: 'finished',
};

function mealStatusFrom(value: unknown): MealStatus | null {
  if (typeof value !== 'string') return null;
  if (value === 'skipped' || value === 'oneBite' || value === 'finished') return value;
  return OLD_ACTIONS[value] ?? null;
}

function recordsFrom(value: unknown, migrated = false): MealRecord[] {
  if (!Array.isArray(value)) return [];
  const seen = new Map<string, MealRecord>();
  for (const entry of value) {
    const source = object(entry);
    const rawMenuName = typeof source?.menuName === 'string' ? source.menuName : source?.mealName;
    if (!source || typeof source.date !== 'string' || typeof rawMenuName !== 'string') continue;
    const status = mealStatusFrom(source.status) ?? mealStatusFrom(source.action);
    if (!status) continue;
    const menuName = normalizeMenuName(rawMenuName);
    const identity = recordIdentity(source.date, menuName);
    seen.set(identity, {
      identity, date: source.date, menuName, status,
      xp: typeof source.xp === 'number' ? source.xp : typeof source.awardedXp === 'number' ? source.awardedXp : 0,
      recordedAt: typeof source.recordedAt === 'number' ? source.recordedAt : typeof source.recordedAt === 'string' ? Date.parse(source.recordedAt) || 0 : 0,
      legacy: migrated || source.legacy === true,
    });
  }
  return [...seen.values()];
}

function stateFrom(value: unknown): AppState | null {
  const source = object(value);
  if (source?.schemaVersion !== 2) return null;
  const records = recordsFrom(source.mealRecords);
  const totalXP = typeof source.totalXP === 'number' && source.totalXP >= 0 ? source.totalXP : 0;
  return {
    schemaVersion: 2,
    profile: profileFrom(source.profile),
    mealRecords: records,
    totalXP,
    xpBaseline: typeof source.xpBaseline === 'number' && source.xpBaseline >= 0 ? source.xpBaseline : Math.max(0, totalXP - records.reduce((sum, record) => sum + record.xp, 0)),
    cache: object(source.cache) as AppState['cache'],
    cacheSavedAt: typeof source.cacheSavedAt === 'number' ? source.cacheSavedAt : null,
  };
}

export function createRepository(storage: StoragePort) {
  async function migrate(): Promise<AppState> {
    const [profileRaw, progressRaw, recordsRaw, cacheRaw] = await Promise.all([
      storage.getItem(LEGACY_KEYS.profile), storage.getItem(LEGACY_KEYS.progress),
      storage.getItem(LEGACY_KEYS.records), storage.getItem(LEGACY_KEYS.cache),
    ]);
    const profile = profileFrom(parse(profileRaw));
    const progress = object(parse(progressRaw));
    const pending = object(progress?.pendingMealFeedback);
    const pendingProgress = object(pending?.progress);
    const records = recordsFrom(pending?.records ?? parse(recordsRaw), true);
    const totalXPSource = pendingProgress ?? progress;
    const totalXP = typeof totalXPSource?.totalXp === 'number' && totalXPSource.totalXp >= 0 ? totalXPSource.totalXp : records.reduce((sum, record) => sum + record.xp, 0);
    const cacheValue = parse(cacheRaw);
    const oldCache = object(Array.isArray(cacheValue) ? cacheValue[0] : cacheValue);
    const oldMeal = object(oldCache?.meal);
    const cacheDate = typeof oldMeal?.date === 'string' ? oldMeal.date : null;
    const savedAt = typeof oldCache?.savedAt === 'number' ? oldCache.savedAt : typeof oldCache?.savedAt === 'string' ? Date.parse(oldCache.savedAt) || null : null;
    const state: AppState = {
      ...EMPTY_STATE,
      profile,
      mealRecords: records,
      totalXP,
      xpBaseline: Math.max(0, totalXP - records.reduce((sum, record) => sum + record.xp, 0)),
      cache: oldCache && oldMeal && cacheDate && profile ? { key: `${profile.school.officeCode}|${profile.school.schoolCode}|${cacheDate}`, meal: oldMeal as unknown as NonNullable<AppState['cache']>['meal'], savedAt: savedAt ?? 0 } : null,
      cacheSavedAt: savedAt,
    };
    await storage.setItem(STATE_KEY, JSON.stringify(state));
    return state;
  }

  return {
    async load() {
      const state = stateFrom(parse(await storage.getItem(STATE_KEY)));
      return state ?? migrate();
    },
    async save(state: AppState) { await storage.setItem(STATE_KEY, JSON.stringify(state)); },
    async clearAllConfirmed() { await storage.clearItems(); },
  };
}
