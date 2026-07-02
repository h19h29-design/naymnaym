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
| 1 | `01-onboarding.jpg` | 첫 실행 인트로 | 고퀄리티 캐릭터, 학교 등록, 체험/보호자 진입 |
| 2 | `02-today-meal.jpg` | 오늘 급식 | 실제/체험 상태 구분, 메뉴별 한 입 도전 진입 |
| 3 | `03-one-bite.jpg` | 한 입 도전 결과 | XP, 뱃지, 공유 카드 안내 |
| 4 | `04-levelup.jpg` | 레벨업 | 캐릭터 성장, EXP, 뱃지 구조 |
| 5 | `05-parent-summary.jpg` | 보호자 요약 | 아이별 기록, 급식 결과 알림, 칭찬 카드 |
| 6 | `06-allergy-safety.jpg` | 알레르기 안전 | 알레르기 주의 메뉴는 한 입 도전보다 안전 확인 우선 |
| 7 | `07-share-card.jpg` | 공유 카드 | iOS 공유 시트로 보낼 카드 생성/저장 진입 |
| 8 | `08-monthly-calendar-live.jpg` | 월간 급식 캘린더 | NEIS 실제 월간 식단 조회 결과 |
| 9 | `09-settings-privacy-support.jpg` | 설정 | 별명 수정, 데이터 관리, 개인정보/지원 접근 |
| 10 | `10-support-guide.jpg` | 지원 안내 | 급식 없음, 샘플 정책, 알레르기 주의, 데이터 삭제 안내 |

## 캡처 기준

- 시뮬레이터: iPhone 16 검증 캡처와 iPhone 17 Pro Max 6.9형 캡처 조합
- 앱 타깃: `TARGETED_DEVICE_FAMILY = 1` iPhone 전용
- 업로드 변환: `1320 x 2868` JPG, alpha 없음
- 상태: 실제 학교 선택 상태에서는 샘플 자동 대체 없음
- 월간 캘린더: 2026년 6월 NEIS 급식 데이터 표시
- 체험/샘플 화면은 체험 모드 배지를 노출해 실제 학교 급식과 구분

## 재캡처가 필요한 경우

- 알레르기 주의 장면을 더 선명하게 보여주려면 알레르기 경고 카드가 상단에 오는 화면으로 재캡처한다.
- 중학생/고등학생 테마를 App Store 전면에 보여주려면 설정에서 사용자 모드를 바꾼 뒤 같은 6.9형 규격으로 다시 캡처한다.
- 사진 기록은 개인정보 노출을 피하기 위해 별도 전면 스크린샷으로 넣지 않는다. 기능 증거와 제출 기준은 `docs/PHOTO_RECORD_RELEASE_EVIDENCE.md`를 따른다.

## 공식 규격 참고

Apple App Store Connect의 screenshot specifications 기준으로 iPhone 6.9형 portrait 허용 크기에는 `1320 x 2868`이 포함된다. 스크린샷은 `.jpeg`, `.jpg`, `.png` 형식으로 1장 이상 10장 이하 업로드한다.
현재 앱은 iPhone 전용 타깃이므로 iPad 스크린샷 세트는 제출 필수 범위에 포함하지 않는다.

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
