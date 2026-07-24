import { Navigate, type RouteObject, useSearchParams } from 'react-router-dom';
import type { Profile } from '../domain/types';

const OnboardingPlaceholder = () => <h1>냠냠레벨업 시작하기</h1>;
const TodayPlaceholder = () => <h1>오늘 급식</h1>;
const SettingsPlaceholder = () => <h1>설정</h1>;

function TodayGate({ profile }: { profile: Profile | null }) {
  const [searchParams] = useSearchParams();
  const isExplicitDemo = searchParams.get('demo') === '1';

  return profile || isExplicitDemo
    ? <TodayPlaceholder />
    : <Navigate to="/onboarding?next=%2Ftoday" replace />;
}

export function routeObjects(profile: Profile | null): RouteObject[] {
  const onboarding = <OnboardingPlaceholder />;

  return [
    {
      path: '/',
      element: <Navigate to={profile ? '/today' : '/onboarding'} replace />,
    },
    { path: '/onboarding', element: onboarding },
    { path: '/today', element: <TodayGate profile={profile} /> },
    {
      path: '/settings',
      element: profile ? <SettingsPlaceholder /> : onboarding,
    },
    {
      path: '*',
      element: <Navigate to={profile ? '/today' : '/onboarding'} replace />,
    },
  ];
}
