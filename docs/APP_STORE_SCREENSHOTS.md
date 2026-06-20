# App Store 스크린샷 산출물

## 업로드 우선순위

App Store Connect에는 먼저 아래 JPG 세트를 업로드한다.

- `docs/app-store-screenshots/iphone-6-9-upload/`
- 규격: iPhone 6.9형, portrait, `1320 x 2868`
- 형식: `.jpg`
- alpha: 없음

원본 PNG는 아래 폴더에 보관한다.

- `docs/app-store-screenshots/iphone-6-9/`
- 규격: iPhone 6.9형, portrait, `1320 x 2868`
- 형식: `.png`
- 비고: `simctl` 캡처 원본이라 alpha 채널이 있다.

iPhone 6.3형 보조 캡처는 아래 위치에 있다.

- `docs/app-store-screenshots/*.png`
- 규격: iPhone 6.3형, portrait, `1206 x 2622`
- 용도: 필요 시 추가 기기 크기 직접 업로드 또는 비교용

## 6.9형 업로드 파일

| 순서 | 파일 | 화면 | 제출 메시지 |
| --- | --- | --- | --- |
| 1 | `01-today-no-meal.jpg` | 오늘 급식 | 실제 학교 선택 상태에서 급식 없음/데이터 없음 상태를 샘플과 구분 |
| 2 | `02-monthly-calendar-live.jpg` | 월간 급식 캘린더 | NEIS 실제 월간 식단 조회 결과 |
| 3 | `03-level-character.jpg` | 레벨업 | 초등학생 테마 캐릭터, EXP, 뱃지 구조 |
| 4 | `04-parent-summary.jpg` | 보호자 요약 | 아이별 기록, 공유 사진, 칭찬 카드 |
| 5 | `05-settings-privacy-support.jpg` | 설정 | 별명 수정, 데이터 관리, 개인정보/지원 접근 |
| 6 | `06-privacy-policy.jpg` | 개인정보 처리방침 | 앱 내부 개인정보 처리방침 접근성 |
| 7 | `07-support-guide.jpg` | 지원 안내 | 급식 없음, 샘플 정책, 알레르기 주의, 데이터 삭제 안내 |

## 캡처 기준

- 시뮬레이터: iPhone 17 Pro Max
- 날짜: 2026-06-20
- 학교: 등촌고등학교
- 상태: 실제 학교 선택, 샘플 자동 대체 없음
- 월간 캘린더: 2026년 6월 NEIS 급식 데이터 표시
- 오늘 급식: 토요일이라 `급식 데이터 없음` 안내 표시

## 재캡처가 필요한 경우

- 첫 3장에 더 강한 판매 메시지가 필요하면 급식이 있는 평일로 캡처한다.
- 중학생/고등학생 테마를 App Store 전면에 보여주려면 설정에서 사용자 모드를 바꾼 뒤 같은 6.9형 규격으로 다시 캡처한다.
- 사진 기록 화면은 실제 급식판 사진 또는 별도 샘플 자산 정책이 확정된 뒤 추가한다.

## 공식 규격 참고

Apple App Store Connect의 screenshot specifications 기준으로 iPhone 6.9형 portrait 허용 크기에는 `1320 x 2868`이 포함된다. 스크린샷은 `.jpeg`, `.jpg`, `.png` 형식으로 1장 이상 10장 이하 업로드한다.

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
