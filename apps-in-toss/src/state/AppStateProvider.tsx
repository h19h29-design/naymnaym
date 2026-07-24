import {
  createContext,
  type Dispatch,
  type PropsWithChildren,
  useContext,
  useEffect,
  useReducer,
} from 'react';
import type { AppRepository } from '../services/repository';
import { reducer, type AppAction, type AppState } from './reducer';

interface AppStateValue {
  state: AppState;
  dispatch: Dispatch<AppAction>;
  repository: AppRepository;
  reload(): Promise<void>;
}

const Context = createContext<AppStateValue | null>(null);

export function AppStateProvider({
  repository,
  children,
}: PropsWithChildren<{ repository: AppRepository }>) {
  const [state, dispatch] = useReducer(reducer, { status: 'loading' });

  const reload = async () => {
    dispatch({ type: 'reset' });
    try {
      dispatch({ type: 'loaded', value: await repository.load() });
    } catch {
      dispatch({ type: 'failed', message: '저장된 정보를 불러오지 못했어요.' });
    }
  };

  useEffect(() => {
    void reload();
  }, [repository]);

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
