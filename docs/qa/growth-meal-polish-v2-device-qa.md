# Growth Meal Polish V2 — Device QA

Date: 2026-09-01 (Asia/Seoul)

Revision: `1d458bf20f02d0c759236bda1798e610f42494ba`

Launch argument: `-native-rebuild-enabled YES`

## Devices

| Device | Simulator ID | Runtime | Result |
| --- | --- | --- | --- |
| Growth QA iPhone 17 Pro Max | `B2A085C2-6172-453A-B1DC-1E8E7631F94B` | iOS 26.5 | Pass |
| Growth QA iPhone 16 | `C1E1FCA1-15B8-4B57-A703-C68709B8E92B` | iOS 26.5 | Pass |
| Growth QA iPhone SE | `6AAAE99E-F469-42E3-9427-5047A6F20A26` | iOS 26.5 | Pass |

Each device received the current Debug app and was launched with the native rebuild flag. The Pro Max capture set was made from a fresh install of the stated revision. The iPhone SE narrow-width checks use native 750×1334 captures.

## Functional and visual checks

| Check | Result | Evidence |
| --- | --- | --- |
| Home character/growth scene | Pass | `01_home_character_growth.jpg` |
| Today tab, forest/character, food icons and menu | Pass | `02_today_meal_icons.jpg` |
| Seven-day weekly preview | Pass | `03_weekly_meal.jpg` |
| Monthly representative-menu calendar | Pass | `04_monthly_meal.jpg` |
| Exact selected day, allergy information, whole-meal nutrition and record CTA | Pass | `05_selected_day_detail.jpg`; date/menu context companion `selected_day_detail_date_context.jpg` |
| Six-state eating picker | Pass | `06_eating_status_picker.jpg` |
| Skipped status, pressure-free copy and nutrient impact | Pass | `07_nutrient_impact_skipped.jpg` |
| One-bite status and nutrient impact | Pass | `08_nutrient_impact_one_bite.jpg` |
| Allergy-safe choice and protective copy | Pass | `09_allergy_safe_choice.jpg` |
| Twelve-stage growth roadmap | Pass | `10_growth_stage_roadmap.jpg`; runtime tree exposed stages 10, 11 and 12 with their names and XP thresholds |
| Next unlock | Pass | `11_growth_next_unlock.jpg` |
| Parent summary | Pass | `12_parent_growth_summary.jpg`; clean `DemoChild 1` test identity |
| iPhone SE selected-day nutrition width | Pass | `13_iphone_se_day_detail.jpg` |
| iPhone SE growth width | Pass | `14_iphone_se_growth.jpg` |
| Store lead candidate | Pass | `15_appstore_lead_candidate.jpg` |
| Explicit demo/experience mode | Pass | `onboarding_demo_clean.jpg`; sample-school/sample-meal disclosure and explicit demo CTA are both visible |
| Empty/failure state | Pass | Parent summary showed no recorded change yet and a non-fabricated school-code/API failure message; `increase_contrast_api_failure.jpg` |

The selected-day sheet is intentionally scrollable. Its date header and all five menu cards cannot share one Pro Max viewport with allergy, nutrition and the CTA. The numbered QA capture prioritizes the fully readable allergy/nutrition/CTA region; the companion capture preserves the exact date and menu context.

On iPhone SE, an accessibility-element coordinate tap missed after the monthly grid translated during scrolling. A single physical tap on the visible September 1 cell opened the correct detail immediately. This was an automation-coordinate miss, not a user interaction defect.

## Accessibility

- Dynamic Type: verified at normal `large` and `accessibility-extra-extra-extra-large`. Parent-summary text wrapped and remained available through the scroll view; no content was silently clipped.
- VoiceOver: enabled through the simulator accessibility preference, relaunched, and inspected through the runtime accessibility tree. Controls exposed meaningful roles/labels, including `아이 연결하기`, `DemoChild 1와 연결되었습니다`, refresh, notification, schedule modes, exact date cells, six eating states, record CTA, and growth stages. VoiceOver was disabled afterward.
- Reduce Motion: enabled, app relaunched and allowed to settle; navigation and content remained usable without motion-dependent disclosure. Restored to disabled.
- Increase Contrast: enabled and visually inspected on the parent/failure state; text, borders and status meaning remained readable. Restored to disabled.
- Tap targets/semantic order: runtime trees preserved discrete targets for daily/weekly/monthly modes, exact day cells, status controls and CTAs. Focused presentation tests also verify date → state → menu → allergy → nutrition → CTA order.
- Final restored settings: Dynamic Type `large`, Increase Contrast `disabled`, Reduce Motion `0`, VoiceOver `0`.

## Automated verification

- Focused XcodeBuildMCP simulator run: `MealScheduleSelectionTests`, `MealPresentationTests`, and `AssetManifestTests` — **65 passed, 0 failed, 0 skipped** in 42.5 seconds.
- Parent verification on the same revision: complete Debug XCTest result — **587 passed, 0 failed, 0 skipped**; Python suite — **75 passed**; generic Release build — exit 0. The source contains 588 `test…` declarations, but `RebuildFeatureGateTests` has mutually exclusive `#if DEBUG` and `#else` cases, so exactly 587 compile in a Debug run. The result bundle includes `testLateOlderSaveInSamePinnedRecorderCannotOverwriteFeedback` from revision `1d458bf`.

## Capture integrity

All 15 required QA files are JPEGs at native simulator resolution. Files 01–12 and 15 are 1320×2868; files 13–14 are 750×1334. Captures contain only synthetic demo/test identities and sample meal data. Store-upload assets were not modified by this QA task.
