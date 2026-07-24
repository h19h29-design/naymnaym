import { useMemo } from 'react';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { AppRepository } from '../services/repository';
import { tossStorage } from '../services/storage';
import { AppStateProvider, useAppState } from '../state/AppStateProvider';
import { routeObjects } from './routes';

const repository = new AppRepository(tossStorage);

function RoutedApp() {
  const { state } = useAppState();
  const profile = state.status === 'ready' ? state.profile : null;
  const router = useMemo(() => createBrowserRouter(routeObjects(profile)), [profile]);

  if (state.status === 'loading') return <p>불러오는 중...</p>;
  if (state.status === 'recoverableError') return <p>{state.message}</p>;

  return <RouterProvider router={router} />;
}

export function App() {
  return (
    <AppStateProvider repository={repository}>
      <RoutedApp />
    </AppStateProvider>
  );
}
