import { ForestNavigation } from '../../components/ForestNavigation';
import { ForestScene } from '../../components/ForestScene';
import { GROWTH_LEVELS, levelFor } from '../../domain/progress';
import { useAppState } from '../../state/AppStateProvider';

export function GrowthPage() {
  const { state } = useAppState();
  const totalXp = state.status === 'ready' ? state.progress.totalXp : 0;
  const hasProfile = state.status === 'ready' && state.profile !== null;
  const level = levelFor(totalXp);
  const next = GROWTH_LEVELS[level.number];
  const span = next ? next[0] - level.threshold : 1;
  const progress = next ? Math.min(1, (totalXp - level.threshold) / span) : 1;

  return (
    <ForestScene className="growth-page" showSettings={hasProfile}>
      <header className="forest-title-card">
        <p className="forest-eyebrow">매일의 한 입이 만든 변화</p>
        <h1>나의 성장</h1>
      </header>

      <section className="character-stage growth-character-stage" aria-label="현재 성장 캐릭터">
        <img
          src={`/growth/level-${level.number}.png`}
          alt={`레벨 ${level.number} ${level.title} 캐릭터`}
        />
        <strong>{level.title}</strong>
      </section>

      <section className="forest-card progress-detail-card" aria-label="성장 진행률">
        <div className="progress-detail-card__row">
          <strong>레벨 {level.number}</strong>
          <span>{totalXp} XP</span>
        </div>
        <div
          className="forest-progress"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(progress * 100)}
          aria-label="다음 성장까지 진행률"
        >
          <span style={{ width: `${progress * 100}%` }} />
        </div>
        <p>
          {next
            ? `다음 성장까지 ${Math.max(next[0] - totalXp, 0)} XP`
            : '모든 성장 단계를 열었어요.'}
        </p>
      </section>

      <section className="forest-card next-growth-card">
        <div>
          <p className="forest-eyebrow">다음에 만날 친구</p>
          <h2>{next?.[1] ?? '최고 레벨 달성'}</h2>
        </div>
        <img
          src={`/growth/level-${Math.min(level.number + 1, GROWTH_LEVELS.length)}.png`}
          alt=""
          aria-hidden="true"
        />
      </section>

      <p className="forest-footer-copy">성장은 천천히, 매일의 한 입으로</p>
      <ForestNavigation />
    </ForestScene>
  );
}
