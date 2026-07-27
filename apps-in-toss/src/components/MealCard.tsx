import type { MealItem } from '@nyam/neis-contract';
import { ALLERGIES, allergyRisk } from '../domain/allergy';
import type { DifficultyReason, EatingStatus } from '../domain/types';
import { MealFeedbackModal } from './MealFeedbackModal';
import { useState } from 'react';

export function MealCard({
  item,
  allergyCodes,
  disabled,
  onRecord,
}: {
  item: MealItem;
  allergyCodes: number[];
  disabled: boolean;
  onRecord(status: EatingStatus, reason?: DifficultyReason | null): void;
}) {
  const [difficultyOpen, setDifficultyOpen] = useState(false);
  const [reason, setReason] = useState<DifficultyReason | null>(null);
  const risks = allergyRisk(item, allergyCodes);
  const riskNames = risks.map((code) => ALLERGIES[code as keyof typeof ALLERGIES]).filter(Boolean);

  const record = (status: EatingStatus, nextReason: DifficultyReason | null = null) => {
    onRecord(status, nextReason);
    if (status === 'smelledOnly' || status === 'half' || status === 'difficultToday') {
      setDifficultyOpen(false);
      setReason(null);
    }
  };

  return (
    <article aria-label={item.name} className="meal-card">
      <div className="meal-card__heading">
        <h2>{item.name}</h2>
        {item.nutrients.length > 0 && <p>영양: {item.nutrients.join(', ')}</p>}
      </div>
      {riskNames.length > 0 && (
        <p className="meal-card__risk" role="note">
          알레르기 안전을 먼저 확인해 주세요 · {riskNames.join(', ')}
        </p>
      )}
      <p className="meal-card__question">어떻게 만났나요?</p>
      <div className="meal-card__actions">
        {risks.length > 0
          ? (
            <button
              className="meal-action meal-action--danger"
              type="button"
              disabled={disabled}
              onClick={() => record('allergyAvoided')}
            >
              알레르기 때문에 피했어요
            </button>
          )
          : (
            <button
              className="meal-action"
              type="button"
              disabled={disabled}
              onClick={() => record('oneBite')}
            >
              한입도전
            </button>
          )}
        <button
          className="meal-action"
          type="button"
          disabled={disabled}
          onClick={() => record('finished')}
        >
          잘먹어요
        </button>
        <button
          className="meal-action"
          type="button"
          disabled={disabled}
          onClick={() => setDifficultyOpen(true)}
        >
          못먹겠어요
        </button>
      </div>
      <MealFeedbackModal
        open={difficultyOpen}
        reason={reason}
        disabled={disabled}
        onOpenChange={setDifficultyOpen}
        onReasonChange={setReason}
        onRecord={record}
      />
    </article>
  );
}
