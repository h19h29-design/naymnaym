import { NavLink, useSearchParams } from 'react-router-dom';

const items = [
  {
    to: '/today',
    label: '오늘',
    icon: (
      <svg viewBox="0 0 32 32" aria-hidden="true">
        <path d="M27 6C16 6 8 11 6 25c8 1 14-1 18-6-5 3-9 3-13 2 6-1 11-5 16-15Z" />
      </svg>
    ),
  },
  {
    to: '/meals',
    label: '급식표',
    icon: (
      <svg viewBox="0 0 32 32" aria-hidden="true">
        <rect x="5" y="7" width="22" height="20" rx="3" />
        <path d="M10 4v6M22 4v6M5 13h22M11 18h3M18 18h3M11 23h3M18 23h3" />
      </svg>
    ),
  },
  {
    to: '/growth',
    label: '성장',
    icon: (
      <svg viewBox="0 0 32 32" aria-hidden="true">
        <path d="M5 26V8m0 18h22M9 21l5-6 5 3 7-9" />
        <path d="m21 9 5-.5-.5 5" />
      </svg>
    ),
  },
  {
    to: '/collection',
    label: '도감',
    icon: (
      <svg viewBox="0 0 32 32" aria-hidden="true">
        <path d="M6 6h7a3 3 0 0 1 3 3v17a4 4 0 0 0-4-4H6V6Zm20 0h-7a3 3 0 0 0-3 3v17a4 4 0 0 1 4-4h6V6Z" />
      </svg>
    ),
  },
] as const;

export function ForestNavigation() {
  const [searchParams] = useSearchParams();
  const suffix = searchParams.get('demo') === '1' ? '?demo=1' : '';

  return (
    <nav className="forest-navigation" aria-label="주요 메뉴">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={`${item.to}${suffix}`}
          className={({ isActive }) => (
            isActive ? 'forest-navigation__item is-active' : 'forest-navigation__item'
          )}
        >
          {item.icon}
          <span>{item.label}</span>
        </NavLink>
      ))}
    </nav>
  );
}
