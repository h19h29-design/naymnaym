# Native Rebuild Meal Loop Parity Matrix

This matrix is the release contract for the child `오늘` meal loop. Every row
starts with no prior XP unless the scenario states otherwise. A normal record
uses `2026-07-25`, menu `시금치나물`, and `oneBite`; the allergy row uses
`allergyAvoided`. Both platforms must keep the title and primary action copy
exactly as written here.

| Scenario | Exact setup | iOS title | Android title | iOS source | Android source | iOS primary action | Android primary action | iOS record result | Android record result | iOS XP | Android XP | iOS motion | Android motion |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Live meal | NEIS returns a non-empty meal; first `oneBite` record | `오늘 급식` | `오늘 급식` | `학교 급식` | `학교 급식` | `오늘 급식 기록하기` — enabled | `오늘 급식 기록하기` — enabled | `RecordMealResult(xpGranted: 18, totalXP: 18, motion: .mealSuccess)` | `RecordMealResult(18, 18, MotionState.MealSuccess)` | `+18`, total `18` | `+18`, total `18` | `.mealSuccess` | `MotionState.MealSuccess` |
| Cached meal while offline | Cached non-empty meal exists; NEIS refresh fails; first `oneBite` record | `오늘 급식` | `오늘 급식` | `저장된 급식` | `저장된 급식` | `오늘 급식 기록하기` — enabled | `오늘 급식 기록하기` — enabled | `RecordMealResult(xpGranted: 18, totalXP: 18, motion: .mealSuccess)` | `RecordMealResult(18, 18, MotionState.MealSuccess)` | `+18`, total `18` | `+18`, total `18` | `.mealSuccess` | `MotionState.MealSuccess` |
| No meal returned | NEIS returns no meal and no cache exists | `오늘 급식` | `오늘 급식` | `급식 정보 없음` | `급식 정보 없음` | `오늘 급식 기록하기` — disabled | `오늘 급식 기록하기` — disabled | No command; no meal record or progress event | No command; no meal record or progress event | unchanged at `0` | unchanged at `0` | `.idle` | `MotionState.Idle` |
| NEIS 503 without cache | NEIS responds 503 and no cache exists | `오늘 급식` | `오늘 급식` | `급식을 불러오지 못했어요` | `급식을 불러오지 못했어요` | `오늘 급식 기록하기` — disabled | `오늘 급식 기록하기` — disabled | No command; no meal record or progress event | No command; no meal record or progress event | unchanged at `0` | unchanged at `0` | `.idle` | `MotionState.Idle` |
| Allergy-risk menu | Live item allergy codes intersect profile; `oneBite` is disabled; `안전하게 피했어요` is recorded first | `오늘 급식` | `오늘 급식` | `학교 급식` | `학교 급식` | `오늘 급식 기록하기` — enabled; sheet prioritizes `안전하게 피했어요`, then `보호자와 확인하기` | `오늘 급식 기록하기` — enabled; sheet prioritizes `안전하게 피했어요`, then `보호자와 확인하기` | `RecordMealResult(xpGranted: 8, totalXP: 8, motion: .mealSuccess)` | `RecordMealResult(8, 8, MotionState.MealSuccess)` | `+8`, total `8` | `+8`, total `8` | `.mealSuccess` | `MotionState.MealSuccess` |
| Duplicate `oneBite` | Same canonical date + normalized menu was already awarded `18`; identical command runs again | `오늘 급식` | `오늘 급식` | `학교 급식` | `학교 급식` | `오늘 급식 기록하기` — enabled | `오늘 급식 기록하기` — enabled | `RecordMealResult(xpGranted: 0, totalXP: 18, motion: .mealSuccess)` | `RecordMealResult(0, 18, MotionState.MealSuccess)` | `+0`, total remains `18`; one positive award only | `+0`, total remains `18`; one positive award only | `.mealSuccess` | `MotionState.MealSuccess` |
| Daily total already at `100` XP | Same day contains `30` base XP + `70` challenge XP; a new `oneBite` command runs | `오늘 급식` | `오늘 급식` | `학교 급식` | `학교 급식` | `오늘 급식 기록하기` — enabled | `오늘 급식 기록하기` — enabled | `RecordMealResult(xpGranted: 0, totalXP: 100, motion: .mealSuccess)` | `RecordMealResult(0, 100, MotionState.MealSuccess)` | `+0`, total remains `100` | `+0`, total remains `100` | `.mealSuccess` | `MotionState.MealSuccess` |

## Required invariants

- `half` remains readable for migration compatibility but is never exposed as
  a new child recording action.
- Cache failure never removes a usable cached meal.
- A duplicate or status transition cannot grant a second positive award for
  the same date and normalized menu.
- Allergy-risk UI disables `oneBite` and puts safety guidance before any eating
  encouragement.
- Empty and failed-without-cache states cannot open the recording sheet.
- XP never decreases for an omitted record, an allergy avoidance, or a
  difficult meal.
- Persisted total XP is positive-only, and a late initial read cannot overwrite
  the newer total returned by a record transaction.
