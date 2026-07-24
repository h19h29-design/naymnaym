import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { AppRepository } from '../services/repository';
import { tossStorage } from '../services/storage';
import { AppStateProvider } from '../state/AppStateProvider';
import { routeObjects } from './routes';

const repository = new AppRepository(tossStorage);
const router = createBrowserRouter(routeObjects());

export function App() {
  return (
    <AppStateProvider repository={repository}>
      <RouterProvider router={router} />
    </AppStateProvider>
  );
}
