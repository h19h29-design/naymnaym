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

const DEFAULT_PROGRESS: Progress = {
  totalXp: 0,
  baseEarnedByDate: {},
  challengeEarnedByDate: {},
};

interface MealCacheEntry {
  key: string;
  meal: MealDay;
  savedAt: string;
}

export interface RepositoryState {
  profile: Profile | null;
  progress: Progress;
  mealRecords: MealRecord[];
  challengeRecords: ChallengeRecord[];
}

export class AppRepository {
  constructor(private readonly storage: KeyValueStorage) {}

  private async read<T>(key: string, fallback: T): Promise<T> {
    const raw = await this.storage.getItem(key);
    if (raw === null) return fallback;

    try {
      return JSON.parse(raw) as T;
    } catch {
      await this.storage.removeItem(key);
      return fallback;
    }
  }

  private write(key: string, value: unknown): Promise<void> {
    return this.storage.setItem(key, JSON.stringify(value));
  }

  async load(): Promise<RepositoryState> {
    const storedProgress = await this.read<Partial<Progress>>(KEYS.progress, {});

    return {
      profile: await this.read<Profile | null>(KEYS.profile, null),
      progress: { ...DEFAULT_PROGRESS, ...storedProgress },
      mealRecords: await this.read<MealRecord[]>(KEYS.mealRecords, []),
      challengeRecords: await this.read<ChallengeRecord[]>(
        KEYS.challengeRecords,
        [],
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

    const entries = await this.read<MealCacheEntry[]>(KEYS.mealCache, []);
    const key = this.cacheKey(school, meal.date);
    const next = [
      { key, meal, savedAt: new Date().toISOString() },
      ...entries.filter((entry) => entry.key !== key),
    ].slice(0, 14);

    await this.write(KEYS.mealCache, next);
  }

  async getCachedMeal(school: School, date: string) {
    const entries = await this.read<MealCacheEntry[]>(KEYS.mealCache, []);
    const entry = entries.find(
      (candidate) => candidate.key === this.cacheKey(school, date),
    );

    return entry ? { meal: entry.meal, source: 'cache' as const } : null;
  }

  async deleteAll(): Promise<void> {
    await Promise.all(Object.values(KEYS).map((key) => this.storage.removeItem(key)));
  }
}
