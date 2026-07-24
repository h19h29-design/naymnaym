import type { ReactNode } from 'react';
import { Navigate, type RouteObject, useSearchParams } from 'react-router-dom';
import { useAppState } from '../state/AppStateProvider';
import type { AppState } from '../state/reducer';
import { OnboardingPage } from '../features/onboarding/OnboardingPage';
import { TodayPage } from '../features/today/TodayPage';

const onboarding = <OnboardingPage />;
const SettingsPlaceholder = () => <h1>설정</h1>;

type ReadyState = Extract<AppState, { status: 'ready' }>;

function ReadyGate({
  children,
}: {
  children(state: ReadyState): ReactNode;
}) {
  const { state } = useAppState();
  if (state.status === 'loading') return <p>불러오는 중...</p>;
  if (state.status === 'recoverableError') return <p>{state.message}</p>;
  return <>{children(state)}</>;
}

function RootGate() {
  return (
    <ReadyGate>
      {({ profile }) => (
        <Navigate to={profile ? '/today' : '/onboarding'} replace />
      )}
    </ReadyGate>
  );
}

function OnboardingGate() {
  const { state } = useAppState();
  if (state.status === 'loading') return <p>불러오는 중...</p>;
  return onboarding;
}

function TodayGate() {
  const [searchParams] = useSearchParams();
  const isExplicitDemo = searchParams.get('demo') === '1';

  return (
    <ReadyGate>
      {({ profile }) => (
        profile || isExplicitDemo
          ? <TodayPage />
          : <Navigate to="/onboarding?next=%2Ftoday" replace />
      )}
    </ReadyGate>
  );
}

function SettingsGate() {
  return (
    <ReadyGate>
      {({ profile }) => (
        profile ? <SettingsPlaceholder /> : onboarding
      )}
    </ReadyGate>
  );
}

function FallbackGate() {
  return (
    <ReadyGate>
      {({ profile }) => (
        <Navigate to={profile ? '/today' : '/onboarding'} replace />
      )}
    </ReadyGate>
  );
}

export function routeObjects(): RouteObject[] {
  return [
    { path: '/', element: <RootGate /> },
    { path: '/onboarding', element: <OnboardingGate /> },
    { path: '/today', element: <TodayGate /> },
    { path: '/settings', element: <SettingsGate /> },
    { path: '*', element: <FallbackGate /> },
  ];
}
