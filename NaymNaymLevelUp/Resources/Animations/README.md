# 냠냠레벨업 Lottie Animations

이 폴더는 앱 번들에 포함되는 Lottie JSON 전용 폴더입니다. 런타임에 외부 URL에서 애니메이션을 내려받지 않습니다.

필수 파일명:

- `mascot_intro.json`: 첫 실행 시 캐릭터 등장
- `mascot_idle_loop.json`: 첫 화면 대기 반복
- `mascot_wave.json`: 손 흔들기 인사
- `mascot_success.json`: 한 입 도전 성공
- `mascot_levelup.json`: 레벨업/뱃지 획득
- `mascot_allergy_warning.json`: 알레르기 주의

현재 포함된 Lottie JSON은 앱 소유 PNG 캐릭터 에셋을 이미지 레이어로 움직이는 1차 버전입니다. JSON에서 참조하는 이미지는 `images/` 하위의 `mascot_onboarding.png`, `mascot_wave_1.png`, `mascot_wave_2.png`, `mascot_jump.png`입니다.

파일이 없거나 로딩에 실패하면 앱은 Asset Catalog의 `mascot_onboarding`, `mascot_wave_1`, `mascot_wave_2`, `mascot_jump` PNG 에셋으로 fallback합니다. 외부 제작 또는 유료 Lottie JSON으로 교체할 때는 상업적 사용 가능 라이선스와 출처를 `THIRD_PARTY_NOTICES.md`에 기록해야 합니다.
