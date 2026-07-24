import { Button, Modal } from '@toss/tds-mobile';
import type { DifficultyReason, EatingStatus } from '../domain/types';

const REASONS: Array<[DifficultyReason, string]> = [
  ['texture', '식감'],
  ['smell', '냄새'],
  ['spicy', '매움'],
  ['color', '색'],
  ['newFood', '새로운 음식'],
  ['allergy', '알레르기'],
  ['other', '기타'],
];

export function MealFeedbackModal({
  open,
  reason,
  disabled,
  onOpenChange,
  onReasonChange,
  onRecord,
}: {
  open: boolean;
  reason: DifficultyReason | null;
  disabled: boolean;
  onOpenChange(open: boolean): void;
  onReasonChange(reason: DifficultyReason): void;
  onRecord(status: Extract<EatingStatus, 'smelledOnly' | 'half' | 'difficultToday'>, reason: DifficultyReason | null): void;
}) {
  return (
    <Modal open={open} onOpenChange={onOpenChange}>
      <Modal.Overlay onClick={() => onOpenChange(false)} />
      <Modal.Content role="dialog" aria-label="어떤 점이 어려웠나요?">
        <h2>어떤 점이 어려웠나요?</h2>
        <p>해당하는 이유를 골라 주세요. 건너뛰어도 괜찮아요.</p>
        {REASONS.map(([value, label]) => (
          <Button
            key={value}
            color="light"
            aria-pressed={reason === value}
            disabled={disabled}
            onClick={() => onReasonChange(value)}
          >
            {label}
          </Button>
        ))}
        <Button disabled={disabled} onClick={() => onRecord('smelledOnly', reason)}>
          냄새만 맡았어요
        </Button>
        <Button disabled={disabled} onClick={() => onRecord('half', reason)}>
          절반 먹었어요
        </Button>
        <Button color="light" disabled={disabled} onClick={() => onRecord('difficultToday', reason)}>
          오늘은 어려웠어요
        </Button>
      </Modal.Content>
    </Modal>
  );
}
