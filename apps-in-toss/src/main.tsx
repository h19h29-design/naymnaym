import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './app/App';
import { AppProviders } from './app/AppProviders';
import { AppStateProvider } from './state/AppStateProvider';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode><AppProviders><AppStateProvider><App /></AppStateProvider></AppProviders></StrictMode>,
);
