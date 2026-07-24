import type { MealDay, School } from '@nyam/neis-contract';
import type {
  ChallengeRecord,
  MealRecord,
  Profile,
  Progress,
} from '../domain/types';
import type { KeyValueStorage } from './storage';

const KEYS = {
  profile: 'nyam-toss:profile:v1',
  progress: 'nyam-toss:progress:v1',
  mealRecords: 'nyam-toss:meal-records:v1',
  challengeRecords: 'nyam-toss:challenge-records:v1',
  mealCache: 'nyam-toss:meal-cache:v1',
} as const;

const DEFAULT_PROGRESS = {
  totalXp: 0,
} as const;

const EATING_STATUSES = new Set([
  'finished',
  'half',
  'oneBite',
  'smelledOnly',
  'difficultToday',
  'allergyAvoided',
]);

const DIFFICULTY_REASONS = new Set([
  'texture',
  'smell',
  'spicy',
  'color',
  'newFood',
  'allergy',
  'other',
]);

const CHALLENGE_KINDS = new Set([
  'variedFoodGroup',
  'streakRecord',
  'allergySafetyCheck',
  'retry',
]);

interface MealCacheEntry {
  key: string;
  meal: MealDay;
  savedAt: string;
}

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === 'string';
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isString);
}

function isNumberArray(value: unknown): value is number[] {
  return Array.isArray(value) && value.every(isFiniteNumber);
}

function isNumberMap(value: unknown): value is Record<string, number> {
  return isRecord(value) && Object.values(value).every(isFiniteNumber);
}

function isSchool(value: unknown): value is School {
  if (!isRecord(value)) return false;

  return isString(value.name)
    && isString(value.officeCode)
    && isString(value.schoolCode)
    && isString(value.region)
    && isString(value.address)
    && (value.schoolType === 'middle' || value.schoolType === 'high');
}

function isProfile(value: unknown): value is Profile {
  if (!isRecord(value)) return false;

  return isString(value.nickname)
    && (value.schoolType === 'middle' || value.schoolType === 'high')
    && isSchool(value.school)
    && value.schoolType === value.school.schoolType
    && isNumberArray(value.allergyCodes)
    && isString(value.createdAt);
}

function isProgress(value: unknown): value is Partial<Progress> {
  if (!isRecord(value)) return false;

  return (value.totalXp === undefined || isFiniteNumber(value.totalXp))
    && (value.baseEarnedByDate === undefined || isNumberMap(value.baseEarnedByDate))
    && (value.challengeEarnedByDate === undefined
      || isNumberMap(value.challengeEarnedByDate));
}

function isMealRecord(value: unknown): value is MealRecord {
  if (!isRecord(value)) return false;

  return isString(value.date)
    && isString(value.mealItemId)
    && isString(value.mealName)
    && isString(value.status)
    && EATING_STATUSES.has(value.status)
    && (value.difficultyReason === null
      || (isString(value.difficultyReason)
        && DIFFICULTY_REASONS.has(value.difficultyReason)))
    && isFiniteNumber(value.awardedXp)
    && isString(value.recordedAt);
}

function isMealRecords(value: unknown): value is MealRecord[] {
  return Array.isArray(value) && value.every(isMealRecord);
}

function isChallengeRecord(value: unknown): value is ChallengeRecord {
  if (!isRecord(value) || !Array.isArray(value.kinds)) return false;

  return isString(value.date)
    && isString(value.mealItemId)
    && value.kinds.every((kind) => isString(kind) && CHALLENGE_KINDS.has(kind))
    && isFiniteNumber(value.awardedXp);
}

function isChallengeRecords(value: unknown): value is ChallengeRecord[] {
  return Array.isArray(value) && value.every(isChallengeRecord);
}

function isMealItem(value: unknown): boolean {
  if (!isRecord(value)) return false;

  return isString(value.id)
    && isString(value.name)
    && isNumberArray(value.allergyCodes)
    && isStringArray(value.nutrients)
    && isStringArray(value.tags)
    && isString(value.sourceRawText);
}

function isNullableString(value: unknown): value is string | null {
  return value === null || isString(value);
}

function isMealDay(value: unknown): value is MealDay {
  if (!isRecord(value) || !Array.isArray(value.menuItems)) return false;

  return isString(value.date)
    && value.menuItems.every(isMealItem)
    && isNullableString(value.calorie)
    && isNullableString(value.nutrition)
    && typeof value.isSample === 'boolean'
    && isNullableString(value.notice);
}

function isMealCacheEntries(value: unknown): value is MealCacheEntry[] {
  return Array.isArray(value) && value.every((entry) => {
    if (!isRecord(entry)) return false;

    return isString(entry.key)
      && isMealDay(entry.meal)
      && !entry.meal.isSample
      && isString(entry.savedAt);
  });
}

function createProgress(stored: Partial<Progress>): Progress {
  return {
    totalXp: stored.totalXp ?? DEFAULT_PROGRESS.totalXp,
    baseEarnedByDate: { ...stored.baseEarnedByDate },
    challengeEarnedByDate: { ...stored.challengeEarnedByDate },
  };
}

export interface RepositoryState {
  profile: Profile | null;
  progress: Progress;
  mealRecords: MealRecord[];
  challengeRecords: ChallengeRecord[];
}

export class AppRepository {
  constructor(private readonly storage: KeyValueStorage) {}

  private async read<T>(
    key: string,
    fallback: T,
    isValid: (value: unknown) => value is T,
  ): Promise<T> {
    const raw = await this.storage.getItem(key);
    if (raw === null) return fallback;

    try {
      const parsed: unknown = JSON.parse(raw);
      if (!isValid(parsed)) throw new Error('Invalid stored data');
      return parsed;
    } catch {
      await this.storage.removeItem(key);
      return fallback;
    }
  }

  private write(key: string, value: unknown): Promise<void> {
    return this.storage.setItem(key, JSON.stringify(value));
  }

  async load(): Promise<RepositoryState> {
    const storedProgress = await this.read<Partial<Progress>>(
      KEYS.progress,
      {},
      isProgress,
    );

    return {
      profile: await this.read<Profile | null>(
        KEYS.profile,
        null,
        (value): value is Profile | null => value === null || isProfile(value),
      ),
      progress: createProgress(storedProgress),
      mealRecords: await this.read<MealRecord[]>(
        KEYS.mealRecords,
        [],
        isMealRecords,
      ),
      challengeRecords: await this.read<ChallengeRecord[]>(
        KEYS.challengeRecords,
        [],
        isChallengeRecords,
      ),
    };
  }

  saveProfile(profile: Profile) {
    return this.write(KEYS.profile, profile);
  }

  saveProgress(progress: Progress) {
    return this.write(KEYS.progress, progress);
  }

  saveRecords(records: MealRecord[]) {
    return this.write(KEYS.mealRecords, records);
  }

  saveChallengeRecords(records: ChallengeRecord[]) {
    return this.write(KEYS.challengeRecords, records);
  }

  private cacheKey(school: School, date: string) {
    return `${school.officeCode}:${school.schoolCode}:${date}`;
  }

  async cacheMeal(school: School, meal: MealDay): Promise<void> {
    if (meal.isSample) return;

    const entries = await this.read<MealCacheEntry[]>(
      KEYS.mealCache,
      [],
      isMealCacheEntries,
    );
    const key = this.cacheKey(school, meal.date);
    const next = [
      { key, meal, savedAt: new Date().toISOString() },
      ...entries.filter((entry) => entry.key !== key),
    ].slice(0, 14);

    await this.write(KEYS.mealCache, next);
  }

  async getCachedMeal(school: School, date: string) {
    const entries = await this.read<MealCacheEntry[]>(
      KEYS.mealCache,
      [],
      isMealCacheEntries,
    );
    const entry = entries.find(
      (candidate) => candidate.key === this.cacheKey(school, date),
    );

    return entry ? { meal: entry.meal, source: 'cache' as const } : null;
  }

  async deleteAll(): Promise<void> {
    await Promise.all(Object.values(KEYS).map((key) => this.storage.removeItem(key)));
  }
}
