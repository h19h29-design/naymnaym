import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { MealDay, MealStatus, Profile } from '../domain/types';
import { applyMealStatus } from '../domain/progress';
import { createNeisClient } from '../services/neisClient';
import { createRepository, EMPTY_STATE } from '../services/repository';
import { getStorage } from '../services/storage';
import { readClientEnv } from '../config/clientEnv';

type Repository = ReturnType<typeof createRepository>;
type NeisClient = ReturnType<typeof createNeisClient>;

interface AppStateContextValue {
  state: typeof EMPTY_STATE;
  ready: boolean;
  client: NeisClient;
  saveProfile(profile: Profile): Promise<void>;
  recordMeal(date: string, menuName: string, status: MealStatus): Promise<void>;
  cacheMeal(key: string, meal: MealDay): Promise<void>;
  clearAllConfirmed(): Promise<void>;
}

const Context = createContext<AppStateContextValue | null>(null);

export function AppStateProvider({ children, repository, client }: { children: ReactNode; repository?: Repository; client?: NeisClient }) {
  const repositoryValue = useMemo(() => repository ?? createRepository(getStorage()), [repository]);
  const clientValue = useMemo(() => client ?? createNeisClient(readClientEnv()), [client]);
  const [state, setState] = useState({ ...EMPTY_STATE });
  const [ready, setReady] = useState(false);
  const stateRef = useRef(state);

  const commit = useCallback(async (next: typeof EMPTY_STATE) => {
    stateRef.current = next;
    setState(next);
    await repositoryValue.save(next);
  }, [repositoryValue]);

  useEffect(() => {
    let live = true;
    repositoryValue.load().catch(() => ({ ...EMPTY_STATE })).then((loaded) => {
      if (!live) return;
      stateRef.current = loaded;
      setState(loaded);
      setReady(true);
    });
    return () => { live = false; };
  }, [repositoryValue]);

  const saveProfile = useCallback(async (profile: Profile) => {
    await commit({ ...stateRef.current, profile });
  }, [commit]);
  const recordMeal = useCallback(async (date: string, menuName: string, status: MealStatus) => {
      const mealRecords = applyMealStatus(stateRef.current.mealRecords, { date, menuName, status, recordedAt: Date.now() });
      await commit({ ...stateRef.current, mealRecords, totalXP: stateRef.current.xpBaseline + mealRecords.reduce((sum, record) => sum + record.xp, 0) });
  }, [commit]);
  const cacheMeal = useCallback(async (key: string, meal: MealDay) => {
    const savedAt = Date.now();
    await commit({ ...stateRef.current, cache: { key, meal, savedAt }, cacheSavedAt: savedAt });
  }, [commit]);
  const clearAllConfirmed = useCallback(async () => {
    await repositoryValue.clearAllConfirmed();
    stateRef.current = { ...EMPTY_STATE };
    setState({ ...EMPTY_STATE });
  }, [repositoryValue]);

  const value = useMemo<AppStateContextValue>(() => ({
    state, ready, client: clientValue, saveProfile, recordMeal, cacheMeal, clearAllConfirmed,
  }), [state, ready, clientValue, saveProfile, recordMeal, cacheMeal, clearAllConfirmed]);

  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useAppState() {
  const value = useContext(Context);
  if (!value) throw new Error('useAppState must be inside AppStateProvider');
  return value;
}
