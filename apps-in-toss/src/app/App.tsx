import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { OnboardingPage } from '../features/onboarding/OnboardingPage';
import { TodayPage } from '../features/today/TodayPage';
import { WeekPage } from '../features/week/WeekPage';
import { SettingsPage } from '../features/settings/SettingsPage';
import { useAppState } from '../state/AppStateProvider';
import { BottomTabs } from '../components/BottomTabs';

export function AppRoutes() {
  const { ready, state } = useAppState();
  const location = useLocation();
  if (!ready) return <main className="center-state" aria-live="polite">기록을 불러오는 중이에요…</main>;
  const onboarding = location.pathname === '/onboarding';
  if (!state.profile && !onboarding) return <Navigate to="/onboarding" replace />;
  return <>
    <Routes>
      <Route path="/onboarding" element={<OnboardingPage />} />
      <Route path="/today" element={<TodayPage />} />
      <Route path="/week" element={<WeekPage />} />
      <Route path="/settings" element={<SettingsPage />} />
      <Route path="*" element={<Navigate to={state.profile ? '/today' : '/onboarding'} replace />} />
    </Routes>
    {state.profile && !onboarding && <BottomTabs />}
  </>;
}

export function App() {
  return <BrowserRouter><AppRoutes /></BrowserRouter>;
}
