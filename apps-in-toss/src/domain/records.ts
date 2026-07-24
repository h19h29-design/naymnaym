import type { MealRecord } from './types';

export function upsertMealRecord(
  records: MealRecord[],
  nextRecord: MealRecord,
): { records: MealRecord[]; newXp: number } {
  const index = records.findIndex((record) =>
    record.date === nextRecord.date &&
    record.mealItemId === nextRecord.mealItemId);
  if (index < 0) {
    return { records: [...records, nextRecord], newXp: nextRecord.awardedXp };
  }

  const updated = [...records];
  updated[index] = {
    ...nextRecord,
    awardedXp: records[index].awardedXp,
  };
  return { records: updated, newXp: 0 };
}
