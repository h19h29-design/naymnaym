# App Store 스크린샷 산출물

App Store Connect에는 아래 폴더의 최신 디자인 JPG만 업로드한다.

- 경로: `docs/app-store-screenshots/iphone-6-9-upload/`
- 규격: iPhone 6.9형 세로, `1320 x 2868`
- 형식: JPG, alpha 없음
- 디자인 기준: 숲 배경, 새 다람쥐 캐릭터, 크림·초록 색상 체계

## 현재 1.3 업로드 매니페스트 (정확히 10장)

아래 표가 현재 1.3 후보의 유일한 App Store Connect 업로드 순서와 파일명이다. 표에 없는 파일은 업로드 폴더에 두지 않는다. 아직 캡처되지 않은 파일은 부모 QA에서 실제 후보 빌드로 캡처하며, 임시 이미지나 이전 UI를 이름만 바꿔 채우지 않는다.

| 순서 | 파일 | 화면 | 핵심 내용 |
| --- | --- | --- | --- |
| 1 | `01-today-companion.jpg` | 오늘 | 움직이는 캐릭터, 오늘 미션과 급식 기록 진입 |
| 2 | `02-character-conversation.jpg` | 캐릭터 대화 | 저장·전송하지 않는 선택형 급식·성장 대화 |
| 3 | `03-daily-meal.jpg` | 일간 급식표 | 선택 전에도 보이는 오늘 메뉴와 대표 영양소 안내 |
| 4 | `04-weekly-meal.jpg` | 주간 급식표 | 요일별 메뉴 비교와 선택 날짜 강조 |
| 5 | `05-monthly-meal.jpg` | 월간 급식표 | 월간 날짜 격자와 날짜별 대표 메뉴 표시 |
| 6 | `06-selected-day-detail.jpg` | 선택 날짜 상세 | 고른 날짜의 메뉴·알레르기·영양 안내 |
| 7 | `07-eating-status-picker.jpg` | 섭취 상태 기록 | 메뉴별 여섯 가지 먹은 정도와 개인 알레르기 강조 |
| 8 | `08-growth-overview.jpg` | 성장 | 캐릭터 현재 단계, 다음 해금과 XP 진행률 |
| 9 | `09-growth-collection.jpg` | 성장 도감 | 캐릭터·영양·도전·꾸준함 수집 현황 |
| 10 | `10-settings.jpg` | 설정 | 학교, 알레르기, 보호자 연결과 데이터 관리 진입 |

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
