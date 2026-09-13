# Android 선택형 영양 코치 구현 보고

## 상태

완료. 기존 dirty 변경을 보존하고 Android 범위만 수정했다. 커밋·푸시·배포·실제 provider/API 호출은 하지 않았다.

## 구현

- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealNutritionCoach.kt`
  - 기존 forest 색상·radius·Material 3 컴포넌트로 선택형 영양 코치 카드 구현
  - 메뉴는 처음에 전체 선택, 질문은 overview/benefits/omission 3종
  - 로컬 안내가 기본이며 기록·XP를 변경하지 않는 가정 안내임을 명시
  - 등록 알레르기 교집합 메뉴는 로컬 경고 후 AI 호출을 우회하고 먹도록 권하지 않음
  - AI 정상 응답을 실제로 받은 경우에만 `AI 응답` 라벨 표시
  - 전송 동의는 개발 AI 모드에서만 표시하고 화면 세션에만 유지
  - overview는 전체 선택 시 `이 식단 어때?`, 부분 선택 시 `이 메뉴 어때?`로 표시
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealNutritionCoachDomain.kt`
  - 메뉴의 알려진 canonical nutrient metadata를 keyword rule보다 우선
  - metadata가 없을 때만 `NutritionRuleEngine.insight(menuName)` 사용
  - 허용 ID 6종을 canonical 순서로 정규화·중복 제거
  - 전체 메뉴 선택 시에만 전체 급식 수치를 포함하고, 부분 선택 시 `wholeMeal={}`로 전송해 메뉴별 영양소와 전체 수치를 혼동하지 않음
  - 메뉴/날짜, 선택, 동의, 등록 알레르기 변경 시 결과·loading 초기화 및 진행 중 coroutine 취소
  - 실패 시 재시도·캐시 없이 로컬 안내와 실패 고지
  - 알레르기 교집합 시 다른 음식의 존재·안전을 가정하지 않고 먹도록 권하지 않음과 보호자·선생님 확인만 안내
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealNutritionCoachClient.kt`
  - 익명 DTO만 직렬화: question, nutrient IDs, 전체 식사의 유효한 protein/carbs/fat, session UUID
  - 메뉴명·학교·날짜·식사 기록·등록 알레르기는 DTO에 존재하지 않음
  - 동의문에 선택한 질문 종류·대표 영양소 ID·전체 선택 시 전체 급식 수치·임시 세션 ID 전송을 명시
  - 0/음수/비유한 수치는 `wholeMeal`에서 누락
  - POST/Bearer/application-json, 연결·읽기 15초, redirect 차단, 16KB 응답 제한, 취소 시 disconnect
  - 응답의 정확한 key 집합, `source=ai`, 각 문자열 1..240자 및 전체 상한 검증
  - DEBUG에서만 `filesDir/meal-coach-development.json`을 최대 4KB로 읽고, 지정된 두 loopback endpoint와 32자 이상 token만 허용
- `android/app/src/main/java/com/h19h29/naymnaymlevelup/rebuild/child/MealScheduleScreen.kt`
  - 일간 NutritionSummary 아래에 통합
  - 주간/월간 SelectedMealInformation의 NutritionSummary 아래에 통합
- `android/app/src/debug/AndroidManifest.xml`
- `android/app/src/debug/res/xml/meal_coach_network_security_config.xml`
  - debug에서만 `10.0.2.2`, `127.0.0.1` cleartext 허용; main/release manifest는 완화하지 않음
- `android/app/src/test/java/com/h19h29/naymnaymlevelup/rebuild/child/MealNutritionCoachTest.kt`
  - 영양소 우선순위/정규화, 익명 DTO, 숫자 누락, 엄격 응답, debug config, 동의/알레르기 우회, 상태 초기화/취소, HTTP transport 검증
- `android/app/src/androidTest/java/com/h19h29/naymnaymlevelup/rebuild/child/MealNutritionCoachScreenTest.kt`
  - 전체 메뉴 기본 선택, 질문 3종, 로컬 응답 및 AI 라벨 비노출 Compose 계약

## TDD 및 검증 결과

- RED: 새 domain API가 없을 때 `MealNutritionCoachTest` 컴파일 실패 확인
- GREEN: `MealNutritionCoachTest` 14개 통과
- RED: `MealNutritionCoach` 화면이 없을 때 Android test 컴파일 실패 확인
- GREEN: `:app:compileDebugAndroidTestKotlin` 성공
- 필수 검증:
  - `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug -I ../scripts/android-test-classpath.gradle --no-daemon --console=plain '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g' --max-workers=2`
  - 결과: `BUILD SUCCESSFUL`
  - unit test: 188개, 실패 0, 오류 0, skip 0
  - debug APK assemble 성공
  - lintDebug 성공
- `git diff --check -- android`: 통과
- API 35 `nyam-companion-qa` (`emulator-5554`) 실제 instrumentation:
  - 기본 글자 테스트 1/1 통과
  - font scale 1.5 테스트 1/1 통과 후 시스템 값을 1.0으로 복원
  - 테스트에서 `developmentConfigEnabled=false`로 실행해 config/key 파일을 읽지 않음
- 화면 캡처(각 1080×2400 PNG):
  - `.impeccable/review/meal-coach-android-initial.png`
  - `.impeccable/review/meal-coach-android-answer.png`
  - `.impeccable/review/meal-coach-android-font-scale-1.5.png`

## 한계와 운영 경계

- 현재 개발 설정 파일과 token이 없으므로 실제 `/v1/meal-coach` 호출은 하지 않았다. 이 상태에서는 로컬 안내가 정상 기본 동작이다.
- 개발 AI 연결은 debug loopback 미리보기 전용이다. 공개 운영 endpoint나 provider key를 앱에 추가하지 않았다.
- 새 캐릭터 자산은 추가하지 않았다. 로딩/성공은 기존 forest UI의 progress 및 상태 라벨로 표현했다.
