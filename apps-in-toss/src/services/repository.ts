import type { AppState, MealDay, MealItem, MealRecord, MealStatus, Profile } from '../domain/types';
import { normalizeMenuName, recordIdentity } from '../domain/progress';
import type { MealReviewResult, NutrientId } from './mealCoachClient';
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

function stringList(value: unknown): string[] | null {
  return Array.isArray(value) && value.every((item) => typeof item === 'string') ? value : null;
}

function mealItemFrom(value: unknown): MealItem | null {
  const source = object(value);
  const allergyCodes = source && Array.isArray(source.allergyCodes) && source.allergyCodes.every((code) => Number.isInteger(code) && code >= 1 && code <= 19) ? source.allergyCodes as number[] : null;
  const nutrients = source ? stringList(source.nutrients) : null;
  const tags = source ? stringList(source.tags) : null;
  if (!source || typeof source.id !== 'string' || typeof source.name !== 'string' || !allergyCodes || !nutrients || !tags || typeof source.sourceRawText !== 'string') return null;
  return { id: source.id, name: source.name, allergyCodes, nutrients, tags, sourceRawText: source.sourceRawText };
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

function mealDayFrom(value: unknown): MealDay | null {
  const source = object(value);
  if (!source || typeof source.date !== 'string' || !/^\d{8}$/.test(source.date) || !Array.isArray(source.menuItems) || source.isSample !== false || !nullableString(source.calorie) || !nullableString(source.nutrition) || !nullableString(source.notice)) return null;
  const menuItems = source.menuItems.map(mealItemFrom);
  if (menuItems.some((item) => item === null)) return null;
  return { date: source.date, menuItems: menuItems as MealItem[], calorie: source.calorie, nutrition: source.nutrition, isSample: source.isSample, notice: source.notice };
}

function cacheFrom(value: unknown): AppState['cache'] {
  const source = object(value);
  const meal = mealDayFrom(source?.meal);
  if (!source || typeof source.key !== 'string' || !source.key || !meal || typeof source.savedAt !== 'number' || !Number.isFinite(source.savedAt)) return null;
  return { key: source.key, meal, savedAt: source.savedAt };
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
  const cache = cacheFrom(source.cache);
  return {
    schemaVersion: 2,
    profile: profileFrom(source.profile),
    mealRecords: records,
    totalXP,
    xpBaseline: typeof source.xpBaseline === 'number' && source.xpBaseline >= 0 ? source.xpBaseline : Math.max(0, totalXP - records.reduce((sum, record) => sum + record.xp, 0)),
    cache,
    cacheSavedAt: cache ? cache.savedAt : null,
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
    const oldMeal = mealDayFrom(oldCache?.meal);
    const cacheDate = oldMeal?.date ?? null;
    const savedAt = typeof oldCache?.savedAt === 'number' ? oldCache.savedAt : typeof oldCache?.savedAt === 'string' ? Date.parse(oldCache.savedAt) || null : null;
    const cache = oldCache && oldMeal && cacheDate && profile && savedAt !== null
      ? { key: `${profile.school.officeCode}|${profile.school.schoolCode}|${cacheDate}`, meal: oldMeal, savedAt }
      : null;
    const state: AppState = {
      ...EMPTY_STATE,
      profile,
      mealRecords: records,
      totalXP,
      xpBaseline: Math.max(0, totalXP - records.reduce((sum, record) => sum + record.xp, 0)),
      cache,
      cacheSavedAt: cache ? savedAt : null,
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

export const MEAL_COACH_SESSION_KEY = 'nyam-toss:meal-coach-session:v1';
const MEAL_REVIEW_PREFIX = 'nyam-toss:meal-review:v1:';

export function mealReviewStorageKey(cacheKey: string) {
  return MEAL_REVIEW_PREFIX + cacheKey;
}

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface SavedMealReview {
  savedAt: number;
  items: Array<{ id: string; name: string }>;
  review: MealReviewResult;
}

function storedReviewFrom(value: unknown): SavedMealReview | null {
  const source = object(value);
  const review = object(source?.review);
  if (!source || !review || typeof source.savedAt !== 'number' || !Number.isFinite(source.savedAt)) return null;
  if (review.source !== 'ai' || review.policyVersion !== 'daily-v2' || typeof review.reviewId !== 'string' || !review.reviewId) return null;
  if (typeof review.day !== 'string' || typeof review.generatedAt !== 'string' || typeof review.model !== 'string') return null;
  if (typeof review.summary !== 'string' || typeof review.caution !== 'string' || typeof review.tip !== 'string') return null;
  if (!Array.isArray(review.menus)) return null;
  const menus = review.menus.map((entry) => {
    const menu = object(entry);
    if (!menu || typeof menu.itemId !== 'string' || typeof menu.nutrient !== 'string' || typeof menu.taste !== 'string' || typeof menu.role !== 'string' || typeof menu.point !== 'string') return null;
    return { itemId: menu.itemId, nutrient: menu.nutrient as NutrientId, taste: menu.taste, role: menu.role, point: menu.point };
  });
  if (menus.some((menu) => menu === null)) return null;
  if (!Array.isArray(source.items)) return null;
  const items = source.items.map((entry) => {
    const item = object(entry);
    return item && typeof item.id === 'string' && typeof item.name === 'string' ? { id: item.id, name: item.name } : null;
  });
  if (items.some((item) => item === null)) return null;
  return {
    savedAt: source.savedAt,
    items: items as SavedMealReview['items'],
    review: {
      source: 'ai',
      reviewId: review.reviewId,
      day: review.day,
      generatedAt: review.generatedAt,
      model: review.model,
      policyVersion: 'daily-v2',
      summary: review.summary,
      menus: menus as MealReviewResult['menus'],
      caution: review.caution,
      tip: review.tip,
    },
  };
}

export function createMealReviewStore(storage: StoragePort) {
  return {
    async sessionId() {
      const existing = await storage.getItem(MEAL_COACH_SESSION_KEY);
      if (existing && UUID_V4.test(existing)) return existing;
      const created = crypto.randomUUID();
      await storage.setItem(MEAL_COACH_SESSION_KEY, created);
      return created;
    },
    async loadReview(cacheKey: string): Promise<SavedMealReview | null> {
      return storedReviewFrom(parse(await storage.getItem(mealReviewStorageKey(cacheKey))));
    },
    async saveReview(cacheKey: string, record: SavedMealReview) {
      await storage.setItem(mealReviewStorageKey(cacheKey), JSON.stringify(record));
    },
  };
}

export type MealReviewStore = ReturnType<typeof createMealReviewStore>;
