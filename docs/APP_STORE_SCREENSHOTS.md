# App Store 스크린샷 산출물

App Store Connect에는 아래 폴더의 최신 디자인 JPG만 업로드한다.

- 경로: `docs/app-store-screenshots/iphone-6-9-upload/`
- 규격: iPhone 6.9형 세로, `1320 x 2868`
- 형식: JPG, alpha 없음
- 디자인 기준: 숲 배경, 새 다람쥐 캐릭터, 크림·초록 색상 체계

## 업로드 순서

| 순서 | 파일 | 화면 | 핵심 내용 |
| --- | --- | --- | --- |
| 1 | `01-today-forest.jpg` | 오늘 급식 | 숲 배경과 새 캐릭터, 오늘의 급식 |
| 2 | `02-meal-recording.jpg` | 급식 기록 | 메뉴별 섭취 경험 기록 |
| 3 | `03-growth.jpg` | 나의 성장 | XP와 다음 캐릭터 해금 |
| 4 | `04-growth-collection.jpg` | 성장 도감 | 현재 캐릭터와 향후 성장 단계 |

구형 냠냠레벨업 캐릭터와 이전 UI가 들어간 이미지는 업로드 대상에서 모두 제외한다.

## 캡처 기준

- 시뮬레이터: iPhone 17 Pro Max
- 앱 타깃: `TARGETED_DEVICE_FAMILY = 1` iPhone 전용
- 앱 디자인: native rebuild 활성화
- 업로드 변환: `1320 x 2868` JPG, alpha 없음
- 개인정보가 포함된 사진 기록 화면은 전면 스크린샷에서 제외

Apple App Store Connect의 screenshot specifications 기준으로 iPhone 6.9형 세로 허용 크기에는 `1320 x 2868`이 포함된다. 스크린샷은 1장 이상 10장 이하 업로드한다.

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
