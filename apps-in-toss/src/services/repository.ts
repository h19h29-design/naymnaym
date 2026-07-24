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

const DEVICE_KEYS = Object.values(KEYS);

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

const OFFICE_CODE_PATTERN = /^[A-Z]\d{2}$/;
const SCHOOL_CODE_PATTERN = /^\d{7}$/;
const MEAL_DATE_PATTERN = /^\d{8}$/;

interface MealCacheEntry {
  key: string;
  meal: MealDay;
  savedAt: string;
}

interface MealFeedbackSnapshot {
  records: MealRecord[];
  progress: Progress;
  challengeRecords: ChallengeRecord[];
}

interface StoredProgress extends Partial<Progress> {
  pendingMealFeedback?: MealFeedbackSnapshot;
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
  return Array.isArray(value) && value.every((item) => Number.isInteger(item) && item >= 1 && item <= 19);
}

function isNumberMap(value: unknown): value is Record<string, number> {
  return isRecord(value) && Object.values(value).every(isFiniteNumber);
}

function isCompleteProgress(value: unknown): value is Progress {
  if (!isRecord(value)) return false;
  const isXp = (item: unknown) => typeof item === 'number' && Number.isInteger(item) && item >= 0;
  const isDateXpMap = (item: unknown) => isRecord(item)
    && Object.entries(item).every(([date, xp]) => MEAL_DATE_PATTERN.test(date) && isXp(xp));
  return isXp(value.totalXp)
    && isDateXpMap(value.baseEarnedByDate)
    && isDateXpMap(value.challengeEarnedByDate);
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

function isProgressValue(value: unknown): value is Partial<Progress> {
  if (!isRecord(value)) return false;

  return (value.totalXp === undefined || isFiniteNumber(value.totalXp))
    && (value.baseEarnedByDate === undefined || isNumberMap(value.baseEarnedByDate))
    && (value.challengeEarnedByDate === undefined
      || isNumberMap(value.challengeEarnedByDate));
}

function isProgress(value: unknown): value is StoredProgress {
  if (!isRecord(value) || !isProgressValue(value)) return false;
  const stored = value as UnknownRecord;
  return stored.pendingMealFeedback === undefined
    || isMealFeedbackSnapshot(stored.pendingMealFeedback);
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

  return isString(value.id) && value.id.length > 0
    && isString(value.name) && value.name.length > 0
    && isNumberArray(value.allergyCodes)
    && isStringArray(value.nutrients)
    && isStringArray(value.tags)
    && isString(value.sourceRawText) && value.sourceRawText.length > 0;
}

function isNullableString(value: unknown): value is string | null {
  return value === null || isString(value);
}

export function isValidLiveMeal(value: unknown, expectedDate?: string): value is MealDay {
  if (!isRecord(value) || !Array.isArray(value.menuItems)) return false;

  return isString(value.date)
    && MEAL_DATE_PATTERN.test(value.date)
    && (expectedDate === undefined || value.date === expectedDate)
    && value.menuItems.every(isMealItem)
    && isNullableString(value.calorie)
    && isNullableString(value.nutrition)
    && value.isSample === false
    && isNullableString(value.notice);
}

function isMealDay(value: unknown): value is MealDay {
  return isValidLiveMeal(value);
}

function isCanonicalCacheKey(key: string, mealDate: string): boolean {
  const parts = key.split(':');
  if (parts.length !== 3) return false;

  const [officeCode, schoolCode, date] = parts;
  return OFFICE_CODE_PATTERN.test(officeCode)
    && SCHOOL_CODE_PATTERN.test(schoolCode)
    && MEAL_DATE_PATTERN.test(date)
    && date === mealDate
    && key === `${officeCode}:${schoolCode}:${date}`;
}

function isMealCacheEntries(value: unknown): value is MealCacheEntry[] {
  if (!Array.isArray(value) || value.length > 14) return false;

  const keys = new Set<string>();
  return value.every((entry) => {
    if (!isRecord(entry) || !isString(entry.key)) return false;

    const valid = isMealDay(entry.meal)
      && isString(entry.savedAt)
      && isCanonicalCacheKey(entry.key, entry.meal.date)
      && !keys.has(entry.key);
    keys.add(entry.key);
    return valid;
  });
}

function isMealFeedbackSnapshot(value: unknown): value is MealFeedbackSnapshot {
  if (!isRecord(value)) return false;
  return isMealRecords(value.records)
    && isCompleteProgress(value.progress)
    && isChallengeRecords(value.challengeRecords);
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
  private operationTail: Promise<void> = Promise.resolve();
  private deletionGeneration = 0;
  private isDeleting = false;
  private deletionPromise: Promise<void> | null = null;

  constructor(private readonly storage: KeyValueStorage) {}

  private serialize<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operationTail.then(operation, operation);
    this.operationTail = result.then(() => undefined, () => undefined);
    return result;
  }

  // A repository is app-scoped: this queue and epoch protect mutations made
  // through this one instance, including the async meal-fetch cache boundary.
  captureMutationEpoch(): number {
    return this.deletionGeneration;
  }

  private serializeMutation<T>(
    operation: () => Promise<T>,
    skipped: T,
    generation = this.captureMutationEpoch(),
  ): Promise<T> {
    if (this.isDeleting || generation !== this.deletionGeneration) return Promise.resolve(skipped);
    return this.serialize(async () => {
      if (this.isDeleting || generation !== this.deletionGeneration) return skipped;
      return operation();
    });
  }

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

  load(): Promise<RepositoryState> {
    return this.serialize(() => this.loadUnsafe());
  }

  private async loadUnsafe(): Promise<RepositoryState> {
    const storedProgress = await this.read<StoredProgress>(
      KEYS.progress,
      {},
      isProgress,
    );

    if (storedProgress.pendingMealFeedback !== undefined) {
      const snapshot = storedProgress.pendingMealFeedback;
      await this.completeMealFeedbackSnapshot(snapshot);
      return {
        profile: await this.read<Profile | null>(
          KEYS.profile,
          null,
          (value): value is Profile | null => value === null || isProfile(value),
        ),
        progress: snapshot.progress,
        mealRecords: snapshot.records,
        challengeRecords: snapshot.challengeRecords,
      };
    }

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
    return this.serializeMutation(() => this.write(KEYS.profile, profile), undefined);
  }

  saveProgress(progress: Progress) {
    return this.serializeMutation(async () => {
      const stored = await this.read<StoredProgress>(KEYS.progress, {}, isProgress);
      if (stored.pendingMealFeedback !== undefined) {
        throw new Error('Cannot save progress while pending feedback recovery exists');
      }
      await this.write(KEYS.progress, progress);
    }, undefined);
  }

  saveRecords(records: MealRecord[]) {
    return this.serializeMutation(() => this.write(KEYS.mealRecords, records), undefined);
  }

  saveChallengeRecords(records: ChallengeRecord[]) {
    return this.serializeMutation(() => this.write(KEYS.challengeRecords, records), undefined);
  }

  async saveMealFeedbackSnapshot(
    records: MealRecord[],
    progress: Progress,
    challengeRecords: ChallengeRecord[],
  ): Promise<void> {
    return this.serializeMutation(async () => {
      const snapshot: MealFeedbackSnapshot = { records, progress, challengeRecords };
      if (!isMealFeedbackSnapshot(snapshot)) throw new Error('Invalid meal feedback snapshot');
      await this.write(KEYS.progress, { ...progress, pendingMealFeedback: snapshot });
      await this.completeMealFeedbackSnapshot(snapshot);
    }, undefined);
  }

  private async completeMealFeedbackSnapshot(snapshot: MealFeedbackSnapshot): Promise<void> {
    await this.write(KEYS.mealRecords, snapshot.records);
    await this.write(KEYS.challengeRecords, snapshot.challengeRecords);
    await this.write(KEYS.progress, snapshot.progress);
  }

  private cacheKey(school: School, date: string) {
    return `${school.officeCode}:${school.schoolCode}:${date}`;
  }

  cacheMeal(school: School, meal: MealDay, mutationEpoch = this.captureMutationEpoch()): Promise<void> {
    return this.serializeMutation(async () => {
      if (!isValidLiveMeal(meal, meal.date)) return;

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
    }, undefined, mutationEpoch);
  }

  getCachedMeal(school: School, date: string) {
    return this.serialize(async () => {
      const entries = await this.read<MealCacheEntry[]>(
        KEYS.mealCache,
        [],
        isMealCacheEntries,
      );
      const entry = entries.find(
        (candidate) => candidate.key === this.cacheKey(school, date),
      );

      return entry && entry.meal.date === date
        ? { meal: entry.meal, source: 'cache' as const }
        : null;
    });
  }

  deleteAll(): Promise<void> {
    if (this.deletionPromise !== null) return this.deletionPromise;

    this.isDeleting = true;
    this.deletionGeneration += 1;
    const operation = this.serialize(async () => {
      const snapshot = new Map(await Promise.all(DEVICE_KEYS.map(async (key) => [
        key,
        await this.storage.getItem(key),
      ] as const)));
      const results = await Promise.allSettled(
        DEVICE_KEYS.map((key) => this.storage.removeItem(key)),
      );
      const failure = results.find((result) => result.status === 'rejected');
      if (failure !== undefined) {
        await Promise.allSettled(DEVICE_KEYS.map((key) => {
          const value = snapshot.get(key) ?? null;
          return value === null
            ? this.storage.removeItem(key)
            : this.storage.setItem(key, value);
        }));
        throw failure.reason;
      }
    });
    const shared = operation.finally(() => {
      if (this.deletionPromise === shared) {
        this.deletionPromise = null;
        this.isDeleting = false;
      }
    });
    this.deletionPromise = shared;
    return shared;
  }
}
