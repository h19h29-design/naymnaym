import {
  createContext,
  type Dispatch,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useReducer,
  useRef,
} from 'react';
import type { AppRepository } from '../services/repository';
import { reducer, type AppAction, type AppState } from './reducer';

interface AppStateValue {
  state: AppState;
  dispatch: Dispatch<AppAction>;
  repository: AppRepository;
  reload(): Promise<boolean>;
}

const Context = createContext<AppStateValue | null>(null);

export function AppStateProvider({
  repository,
  children,
}: PropsWithChildren<{ repository: AppRepository }>) {
  const [state, dispatch] = useReducer(reducer, { status: 'loading' });
  const activeRef = useRef(false);
  const hasReadyStateRef = useRef(false);
  const generationRef = useRef(0);
  const repositoryRef = useRef(repository);

  const reload = useCallback(async () => {
    if (!activeRef.current || repositoryRef.current !== repository) return false;
    const generation = ++generationRef.current;
    const preserveReadyState = hasReadyStateRef.current;
    if (!preserveReadyState) dispatch({ type: 'reset' });
    try {
      const value = await repository.load();
      if (
        activeRef.current
        && generation === generationRef.current
        && repositoryRef.current === repository
      ) {
        dispatch({ type: 'loaded', value });
        hasReadyStateRef.current = true;
        return true;
      }
      return false;
    } catch {
      if (!preserveReadyState && (
        activeRef.current
        && generation === generationRef.current
        && repositoryRef.current === repository
      )) {
        dispatch({ type: 'failed', message: '저장된 정보를 불러오지 못했어요.' });
      }
      return false;
    }
  }, [repository]);

  useEffect(() => {
    repositoryRef.current = repository;
    hasReadyStateRef.current = false;
    activeRef.current = true;
    void reload();
    return () => {
      activeRef.current = false;
      generationRef.current += 1;
    };
  }, [reload, repository]);

  return (
    <Context.Provider value={{ state, dispatch, repository, reload }}>
      {children}
    </Context.Provider>
  );
}

export function useAppState(): AppStateValue {
  const value = useContext(Context);
  if (value === null) throw new Error('AppStateProvider is required');
  return value;
}
