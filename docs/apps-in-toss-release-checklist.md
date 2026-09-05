# Apps in Toss Lite v2 release checklist

## Phase 3 로컬 후보

- [x] appName `nyam-levelup`, 표시 이름 `급식레벨업`, console entry `/today` 확인
- [x] SDK 3.3.0 config와 TDS 2.5.1 lockfile
- [x] production env fail-closed, `.env.local` ignored/mode 600
- [x] 네 경로와 오늘/주간/설정 세 탭
- [x] 초·중·고 school type, 선택 별명, allergy
- [x] live/cache/no-data/backend/network/Origin/rate 화면 분리
- [x] explicit demo만 sample 표시, demo 저장 없음
- [x] v1 migration, totalXP 보존, legacy key 비삭제
- [x] status 교체와 daily cap, allergy one-bite 잠금
- [x] 실제 날짜 7일 range 한 번
- [x] Device.openURL 개인정보/문의 링크
- [x] 360px, safe-area, 44px touch target, focus, reduced motion
- [x] 검증된 7개 WebP와 8~12 placeholder
- [x] web/AIT verifier가 100MB, stage asset, secret marker, non-anon JWT, appName 검사

## Phase 4 콘솔 및 실기기

- [x] 기존 mini-app 57196에 test bundle `20260905-15` 등록 (SDK 3.3.0)
- [x] iOS QR: Toss 앱에서 bundle 실행 및 초기 흰 화면 없음
- [ ] iOS QR 세부: 학교 재검색, 기록 저장, 재실행 보존, 뒤로가기
- [ ] Android QR: 학교 검색, 오늘/주간, 저장, 재실행, 뒤로가기
- [x] live/private 두 Origin OPTIONS/POST와 CORS 확인
- [x] 새 bundle의 NAS safe log 확인 (`fetchMealsRange` 200, `fetchMeals` 404 no-data)
- [x] 개인정보 처리방침·문의·데이터 안전 URL HTTP 200 및 Lite v2 문구 공개 반영
- [ ] 개인정보 처리방침과 문의 URL 실제 QR WebView 접근
- [x] iOS QR에서 앱 초기 로딩과 흰 화면 없음 확인
- [x] console icon/표시 이름 최종 육안 대조

test deployment ID는 `01a06cfb-ab5f-705d-b1b6-815f815f6cb0`이다. 콘솔 QR과 `intoss-private://nyam-levelup` scheme 발급 뒤 사용자가 iOS Toss 앱에서 실행을 확인했다. 같은 시점의 NAS safe log에는 `fetchMeals` 404 두 건과 `fetchMealsRange` 200 한 건이 기록됐다. 학교 재검색, 기록 저장, 재실행 보존, 뒤로가기는 각각 증거를 확보하지 않아 완료 표시하지 않는다. Android는 미검증 상태다.

사용자가 Android 미검증 위험을 명시적으로 수용한 뒤 2026-09-05 09:55 KST `20260905-15`의 검토 요청을 제출했다. 콘솔 상태는 `검토 중`이며 `출시하기`는 누르지 않았다.
