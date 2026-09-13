# Android 선택형 영양 코치 — 구현 요구

작업 디렉터리: `/Users/mac-mini/Documents/냠냠/.worktrees/ios-growth-meal-polish-v2`. 현재 dirty 변경은 전부 보존. 다른 파일은 부모가 편집. 커밋/푸시/배포/새 에이전트/외부 모델/비밀 파일 읽기 금지.

범위: Android의 새 파일 `rebuild/child/MealNutritionCoach.kt`, 별도 domain/client 파일 필요하면 추가, unit test, `MealScheduleScreen.kt`의 일간 NutritionSummary 아래 및 주간/월간 SelectedMealInformation에 통합. 기존 스타일과 Compose 동작 유지. 오늘 탭은 변경하지 않음.

UI: 선택한 급식의 메뉴 선택(기본 전체), 질문 3개 `이 식단 어때?`(overview), `먹으면 어떤 도움이 돼?`(benefits), `남기면 어떻게 보완해?`(omission). 실제 기록을 변경하지 않는 가정 질문. 로컬 안내가 기본. 이름/학교/날짜/개인 식사 기록/등록 알레르기는 전송하지 않음. 등록 알레르기 경고는 로컬에만 표시하며 관련메뉴 먹도록 권유 금지. 서버 전송 전에 화면 세션 한정 명시 동의 체크(기본 꺼짐). 로컬기본설정시 전송동의 불필요/비활성.

기존 `NutritionRuleEngine(context.assets).insight(menuName)`와 meal.nutrients의 canonical IDs를 이용해 대표 영양소 추출. 서버에는 영양소 ID와 전체식단 3개 수치만. 메뉴 이름은 서버 전송에서 제외. 전체식사 수치를 반찬별 수치로 나누지 않음. 0/비유한/음수는 수치없음 취급. 1레벨 캐릭터 작은 기존 정지/애니 자산 필요하면 80dp, 새 자산생성 없음. 작업로딩은 thinking, 성공encouraging, 기본idle/reducedmotion존중. 캐릭터추가는필수아님(기존대화와단순결합보다부모추가가능).

전송 규격:
POST /v1/meal-coach, Authorization Bearer <server client accessToken>, Content-Type application/json.
요청 JSON `{question:"overview"|"benefits"|"omission",nutrients:["fiber"|"vitamin"|"protein"|"iron"|"calcium"|"carbohydrate"],wholeMeal:{protein?:number,carbs?:number,fat?:number},sessionId:UUID}`. 응답 `{source:"ai",summary:string,benefit:string,caution:string,tip:string}`. 문자열각1..240자(최대전체1200), JSON키추가/누락과 source불일치거부. HTTP오류시캐시/자동재시도없이 기본안내+실패고지. 연결/읽기timeout15초, 리다이렉트불가, 응답16KB한도, coroutine취소시 이전응답반영금지.

디버그 전용 설정: 앱 `context.filesDir/meal-coach-development.json`에서 `{endpoint,accessToken}` 읽기. BuildConfig.DEBUG=false에서는 파일을 절대읽지말고 nil. 허용 endpoint는 http://10.0.2.2:64918/v1/meal-coach 또는 http://127.0.0.1:64918/v1/meal-coach ONLY. 이는 개발 미리보기용, 공개운영불가. Go provider key를 앱에넣지않음. 빈토큰/32글자미만/큰파일/다른host경로거부. Cleartext가막히면 DEBUG전용 manifest/network security config에서 이2host만 허용;main/release보안완화금지. 현재 설정파일 없으므로 offline fallback UI가정상.

로컬안내: 대표영양소이름+일반역할, 먹으면공급받을수있음, 남기면한끼로결핍단정불가/다른식사에서다양하게보완, 정확한섭취량/알레르기안전보장/체중/키진단금지. 선택식단변경시 결과/선택메뉴/로딩초기화하고 취소. 기존식사기록/XP변경금지. AI연결활성은실제정상응답받은경우만라벨표시.

TDD: 새영양소정규화/개인필드없는DTO/숫자누락/응답검증/선택날짜초기화 등 실제동작테스트. org.json 일반JVM테스트가 mock문제로막히면 기존Java JSONObject 테스트구조확인 또는 순수Kotlin도메인으로분리.
검증: android/에서 `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug -I ../scripts/android-test-classpath.gradle --no-daemon --console=plain '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g' --max-workers=2`. 필요 instrumentation 추가. 최종보고서는 같은 plan폴더 `2026-09-13-meal-coach-android-report.md`에 파일/테스트/결과/한계 기록. 응답은 상태/요약만.
