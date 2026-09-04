import { getLevel, getNextLevel } from '../domain/progress';

export function GrowthCard({ totalXP }: { totalXP: number }) {
  const level = getLevel(totalXP);
  const next = getNextLevel(totalXP);
  return <section className="growth-card" aria-labelledby="growth-title">
    {level.level <= 7
      ? <img src={`/growth/level-${level.level}.webp`} alt={`${level.title} 캐릭터`} width="220" height="220" />
      : <div className="art-placeholder" role="img" aria-label={`${level.title} 캐릭터 그림 준비 중`}>그림 준비 중</div>}
    <div><p className="eyebrow">레벨 {level.level}</p><h2 id="growth-title">{level.title}</h2>
      <strong>{totalXP} XP</strong>
      <p>{next ? `다음 레벨까지 ${next.threshold - totalXP} XP` : '최고 레벨을 달성했어요!'}</p>
    </div>
  </section>;
}
