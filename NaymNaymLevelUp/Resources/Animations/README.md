# 냠냠레벨업 Lottie Animations

이 폴더는 앱 번들에 포함되는 Lottie JSON 전용 폴더입니다. 런타임에 외부 URL에서 애니메이션을 내려받지 않습니다.

필수 파일명:

- `mascot_intro.json`: 첫 실행 시 캐릭터 등장
- `mascot_idle_loop.json`: 첫 화면 대기 반복
- `mascot_wave.json`: 손 흔들기 인사
- `mascot_success.json`: 한 입 도전 성공
- `mascot_levelup.json`: 레벨업/뱃지 획득
- `mascot_allergy_warning.json`: 알레르기 주의

현재 실제 캐릭터 Lottie JSON은 포함하지 않습니다. 파일이 없으면 앱은 `mascot_onboarding`, `mascot_wave_1`, `mascot_wave_2`, `mascot_jump` PNG 에셋으로 fallback합니다. 최종 출시용 캐릭터 Lottie JSON을 추가할 때는 상업적 사용 가능 라이선스와 출처를 `THIRD_PARTY_NOTICES.md`에 기록해야 합니다.
