import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

const FOREST_LAYERS = [
  ['sky', 'forest_home_sky.png'],
  ['distant', 'forest_home_distant_trees.png'],
  ['midground', 'forest_home_midground_trees.png'],
  ['ground', 'forest_home_ground.png'],
  ['foreground', 'forest_home_foreground_leaves.png'],
] as const;

export function ForestScene({
  children,
  className = '',
  showSettings = true,
}: {
  children: ReactNode;
  className?: string;
  showSettings?: boolean;
}) {
  return (
    <main className={`forest-shell ${className}`.trim()}>
      <div className="forest-backdrop" aria-hidden="true">
        {FOREST_LAYERS.map(([layer, filename]) => (
          <img
            key={layer}
            className={`forest-layer forest-layer--${layer}`}
            src={`/forest/${filename}`}
            alt=""
          />
        ))}
        <div className="forest-light" />
      </div>
      <div className="forest-content">
        {showSettings ? (
          <div className="forest-toolbar">
            <span className="forest-toolbar__brand">급식레벨업</span>
            <Link className="forest-settings-link" to="/settings" aria-label="설정 열기">
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path d="M12 8.25a3.75 3.75 0 1 0 0 7.5 3.75 3.75 0 0 0 0-7.5Z" />
                <path d="M19.1 13.2c.05-.4.05-.8 0-1.2l1.7-1.3-1.7-3-2 .8a8 8 0 0 0-1-.6l-.3-2.2h-3.5L12 7.9a8 8 0 0 0-1 .6l-2-.8-1.7 3L9 12c-.05.4-.05.8 0 1.2l-1.7 1.3 1.7 3 2-.8c.3.2.65.4 1 .6l.3 2.2h3.5l.3-2.2c.35-.2.7-.4 1-.6l2 .8 1.7-3-1.7-1.3Z" />
              </svg>
            </Link>
          </div>
        ) : null}
        {children}
      </div>
    </main>
  );
}
