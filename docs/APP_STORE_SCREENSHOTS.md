# App Store 스크린샷 산출물

App Store Connect에는 아래 폴더의 최신 디자인 JPG만 업로드한다.

- 경로: `docs/app-store-screenshots/iphone-6-9-upload/`
- 규격: iPhone 6.9형 세로, `1320 x 2868`
- 형식: JPG, alpha 없음
- 디자인 기준: 숲 배경, 새 다람쥐 캐릭터, 크림·초록 색상 체계

## 현재 1.2 업로드 매니페스트 (정확히 10장)

아래 표가 현재 1.2 후보의 유일한 App Store Connect 업로드 순서와 파일명이다. 표에 없는 파일은 업로드 폴더에 두지 않는다. 아직 캡처되지 않은 파일은 부모 QA에서 실제 후보 빌드로 캡처하며, 임시 이미지나 이전 UI를 이름만 바꿔 채우지 않는다.

| 순서 | 파일 | 화면 | 핵심 내용 |
| --- | --- | --- | --- |
| 1 | `01-onboarding-demo.jpg` | 온보딩/체험 모드 | 첫 실행, 아이로 시작, 명시적 체험 모드와 샘플 안내 |
| 2 | `02-today-meal-icons.jpg` | 오늘 급식 | 음식 아이콘, 오늘 메뉴, 숲 배경과 캐릭터 |
| 3 | `03-weekly-meal.jpg` | 주간 급식표 | 7일 급식, 오늘 강조, 대표 메뉴 미리보기 |
| 4 | `04-monthly-meal.jpg` | 월간 급식표 | 월간 날짜 격자, 음식 아이콘, 메뉴 개수 |
| 5 | `05-selected-day-detail.jpg` | 선택 날짜 상세 | 고른 급식의 메뉴·알레르기·전체 영양 요약과 기록 버튼 |
| 6 | `06-eating-status-picker.jpg` | 섭취 상태 기록 | 메뉴별 여섯 가지 먹은 정도 선택 |
| 7 | `07-allergy-safe-choice.jpg` | 알레르기 주의 | 알레르기로 피한 선택과 학교 안내/보호자 판단 우선 안내 |
| 8 | `08-growth-stage-roadmap.jpg` | 성장 로드맵 | 12단계 성장 단계, 현재 단계와 해금 기준 |
| 9 | `09-growth-next-unlock.jpg` | 다음 해금 | 다음 캐릭터·보상과 필요한 XP |
| 10 | `10-parent-growth-summary.jpg` | 부모 요약 | 아이별 성장·급식 기록과 선택 공유 상태 |

구형 냠냠레벨업 캐릭터, 이전 UI, 개인정보가 포함된 사진 기록 화면은 업로드 대상에서 모두 제외한다.

## 캡처 기준

- 시뮬레이터: iPhone 17 Pro Max
- 앱 타깃: `TARGETED_DEVICE_FAMILY = 1` iPhone 전용
- 앱 디자인: native rebuild 활성화
- 업로드 변환: `1320 x 2868` JPG, alpha 없음
- 검증 기준: `scripts/verify-release-readiness.sh`가 위 10개 파일을 각각 검사하고, 누락·추가 파일을 모두 거부한다.
- 개인정보가 포함된 사진 기록 화면은 전면 스크린샷에서 제외

Apple App Store Connect의 screenshot specifications 기준으로 iPhone 6.9형 세로 허용 크기에는 `1320 x 2868`이 포함된다. 현재 후보는 위 매니페스트의 10장을 모두 캡처한 뒤 업로드한다.

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
