import { Button } from '@toss/tds-mobile';
import { useMemo, useState } from 'react';
import { hasAllergyRisk } from '../../domain/allergy';
import type { MealItem, MealStatus } from '../../domain/types';

export function QuickRecordButton({ date, items, allergyCodes, recordMeal, onComplete }: {
  date: string;
  items: MealItem[];
  allergyCodes: number[];
  recordMeal: (date: string, menuName: string, status: MealStatus) => Promise<void>;
  onComplete: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [recording, setRecording] = useState(false);
  const riskyCount = useMemo(
    () => items.filter((item) => hasAllergyRisk(item.allergyCodes, allergyCodes)).length,
    [allergyCodes, items],
  );

  const recordAll = async () => {
    setRecording(true);
    try {
      for (const item of items) {
        const status: MealStatus = hasAllergyRisk(item.allergyCodes, allergyCodes) ? 'skipped' : 'finished';
        await recordMeal(date, item.name, status);
      }
      setConfirming(false);
      onComplete();
    } finally {
      setRecording(false);
    }
  };

  if (!confirming) return <div className="quick-record"><Button
    aria-label="오늘 급식 전체를 한 번에 기록하기"
    disabled={items.length === 0}
    onClick={() => setConfirming(true)}
  >오늘 다 잘먹었어요</Button></div>;

  return <div className="quick-record-confirm" role="group" aria-label="오늘 급식 전체 기록 확인">
    <p>모든 메뉴를 한 번에 기록할까요?</p>
    {riskyCount > 0 && <p>알레르기 주의 메뉴 {riskyCount}개는 안 먹음으로 기록해요.</p>}
    <div className="button-row">
      <Button color="light" disabled={recording} onClick={() => setConfirming(false)}>취소</Button>
      <Button aria-label="오늘 급식 전체 기록 확정" disabled={recording} onClick={() => void recordAll()}>
        {recording ? '기록 중…' : '기록할게요'}
      </Button>
    </div>
  </div>;
}
