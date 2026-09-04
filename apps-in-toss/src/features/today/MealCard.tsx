import type { MealItem, MealStatus } from '../../domain/types';

const options: Array<{ status: MealStatus; label: string }> = [
  { status: 'skipped', label: '안 먹음' },
  { status: 'oneBite', label: '한 입 도전' },
  { status: 'finished', label: '잘 먹음' },
];

export function MealCard({ item, risky, selected, onStatus }: {
  item: MealItem;
  risky: boolean;
  selected?: MealStatus;
  onStatus: (status: MealStatus) => void;
}) {
  return <article className={risky ? 'meal-card risk' : 'meal-card'}>
    <div className="meal-name-row">
      <h3>{item.name}</h3>
      {risky && <span className="risk-badge">알레르기 주의</span>}
    </div>
    {risky && <p className="safety-message">알레르기 가능성이 있어요. 학교 안내와 보호자 확인이 먼저예요.</p>}
    <div className="status-buttons">
      {options.map(({ status, label }) => <button
        key={status}
        type="button"
        aria-label={`${item.name} ${label}`}
        aria-pressed={selected === status}
        disabled={risky && status === 'oneBite'}
        onClick={() => onStatus(status)}
      >{label}</button>)}
    </div>
  </article>;
}
