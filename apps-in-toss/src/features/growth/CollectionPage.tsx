import { ForestNavigation } from '../../components/ForestNavigation';
import { ForestScene } from '../../components/ForestScene';
import { GROWTH_LEVELS, levelFor } from '../../domain/progress';
import { useAppState } from '../../state/AppStateProvider';

export function CollectionPage() {
  const { state } = useAppState();
  const totalXp = state.status === 'ready' ? state.progress.totalXp : 0;
  const hasProfile = state.status === 'ready' && state.profile !== null;
  const currentLevel = levelFor(totalXp).number;

  return (
    <ForestScene className="collection-page" showSettings={hasProfile}>
      <header className="forest-title-card">
        <p className="forest-eyebrow">한 입씩 열리는 일곱 단계</p>
        <h1>성장 도감</h1>
      </header>

      <section className="collection-grid" aria-label="성장 캐릭터 목록">
        {GROWTH_LEVELS.map(([threshold, title], index) => {
          const level = index + 1;
          const unlocked = level <= currentLevel;
          return (
            <article className={unlocked ? 'collection-card' : 'collection-card is-locked'} key={title}>
              <div className="collection-card__image">
                <img
                  src={`/growth/level-${level}.png`}
                  alt={unlocked ? `${title} 캐릭터` : ''}
                  aria-hidden={!unlocked}
                />
              </div>
              <span>레벨 {level}</span>
              <h2>{unlocked ? title : `${threshold} XP에 공개`}</h2>
            </article>
          );
        })}
      </section>
      <ForestNavigation />
    </ForestScene>
  );
}
