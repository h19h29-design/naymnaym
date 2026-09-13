# 준비된 캐릭터 대화와 동작

- iOS/Android 오늘 탭 → 냠냠이와 이야기하기.
- 6개 선택 주제, 10개 준비된 응답(인사/한 입/어려운 반찬/지침은 각 2개).
- AI 호출, 키, 서버 저장, 자유 입력, 음성 없음. 대화는 화면 세션에만 유지, 최대 12개 메시지. 실제 식사 기록과 경험치를 수정하지 않음.
- 1레벨 캐릭터에 대기/듣기/생각/응원 4종 추가. 상위 단계의 기존 캐릭터를 1레벨로 대체하지 않음.
- 새 클립 각각 8개 생성 키 포즈를 121개 재생 프레임으로 보간. 400×400, 25.6fps, 약 4.73초. 121개의 독립 제작 포즈가 아님.
- 기존 인사/먹기/성장 클립은 그대로 유지.
- 원본: 내장 ImageGen, `atlas-generation-prompt.txt`; 체크 배경 수정: `atlas-key-prompt.txt`. Higgsfield와 외부 유료 생성 API 미사용.
- 변환: `node scripts/build-conversation-clips.mjs design-output/2026-09-13-companion-dialogue/reactions-atlas.png`.
- 최종 APNG: `NaymNaymLevelUp/Resources/MascotRig/Companion/`, WebP 및 정지컷: `android/app/src/main/assets/companion/`.
- OpenCode Go 사용자 대화 연결은 보류. 일반 앱 사용이 허용된 공급 경로, 아동 데이터 처리, 비용 한도 확인 전 실제 호출/배포 금지.

## 검증

검증 결과는 프로젝트 루트 `design-qa.md`의 2026-09-13 항목에 기록한다.

- iOS 전체 테스트 596개 통과, Android 전체 단위 테스트 174개 통과.
- Android 빌드·lint 및 새 대화 UI 계측 테스트(기본/큰 글자) 통과.
- Android 테스트 클래스패스의 한글 경로 문제는 다음 명시적 우회로 검증했다 (`android/`에서 실행):

```sh
./gradlew :app:testDebugUnitTest :app:assembleDebugAndroidTest :app:assembleDebug :app:lintDebug -I ../scripts/android-test-classpath.gradle --no-daemon --console=plain '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g' --max-workers=2
```

`four-reactions-preview.mp4`에서 대기·듣기·생각·응원을 한 번에 볼 수 있다. 앱 시뮬레이터에서는 오늘 탭의 대화 버튼으로 확인한다. 실제 AI 연결과 배포는 하지 않았다.
