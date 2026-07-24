import { useEffect, useState } from 'react';
import { levelFor } from '../domain/progress';

export function GrowthHeader({ totalXp }: { totalXp: number }) {
  const level = levelFor(totalXp);
  const [changed, setChanged] = useState(false);

  useEffect(() => {
    setChanged(true);
    const timer = window.setTimeout(() => setChanged(false), 180);
    return () => window.clearTimeout(timer);
  }, [totalXp]);

  return (
    <section aria-label="성장 현황" className={changed ? 'growth-header growth-header--changed' : 'growth-header'}>
      <img src={`/growth/level-${level.number}.png`} alt={`${level.title} 캐릭터`} />
      <strong>Lv.{level.number} {level.title}</strong>
      <span>{totalXp} XP</span>
    </section>
  );
}
