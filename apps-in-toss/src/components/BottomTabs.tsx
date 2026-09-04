import { NavLink } from 'react-router-dom';

const tabs = [
  ['/today', '오늘', '🍱'], ['/week', '주간', '📅'], ['/settings', '설정', '⚙️'],
] as const;

export function BottomTabs() {
  return <nav className="bottom-tabs" aria-label="주요 메뉴">
    {tabs.map(([to, label, icon]) => <NavLink key={to} to={to} className={({ isActive }) => isActive ? 'active' : ''}>
      <span aria-hidden="true">{icon}</span><span>{label}</span>
    </NavLink>)}
  </nav>;
}
