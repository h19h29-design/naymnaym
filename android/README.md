# 급식레벨업 Android 테스트 앱

이 폴더는 iOS 앱과 같은 NEIS/보호자 초대 흐름을 Android에서 테스트하기 위한 네이티브 Android 앱입니다.

## 로컬 설정

`android/local.properties`는 Git에 커밋하지 않습니다. 아래 값이 필요합니다.

```properties
sdk.dir=/Users/mac-mini/Library/Android/sdk
NEIS_API_KEY=...
PARENT_SYNC_API_BASE_URL=https://rytfbovyyzjlrtzdzldo.supabase.co/functions/v1/parent-sync
ANDROID_KEYSTORE_FILE=naymnaym-upload.jks
ANDROID_KEYSTORE_PASSWORD=...
ANDROID_KEY_ALIAS=naymnaym-upload
ANDROID_KEY_PASSWORD=...
```

## 빌드

```bash
cd android
./gradlew :app:assembleDebug :app:bundleRelease :app:lintDebug --no-daemon
```

결과물:

- Debug APK: `android/app/build/outputs/apk/debug/app-debug.apk`
- Play 업로드용 AAB: `android/app/build/outputs/bundle/release/app-release.aab`

## 설치

```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

## 테스트 링크 배포

Android도 테스트 링크 배포가 가능합니다. Play Console에서 앱을 만든 뒤 `app-release.aab`를 다음 중 하나로 업로드합니다.

- Internal testing: 지정 테스터 그룹에 테스트 링크 배포
- Internal app sharing: 빠른 APK/AAB 공유 링크 생성

Play Console 최초 설정에는 개발자 계정, 앱 생성, 패키지명 `com.h19h29.naymnaymlevelup`, 앱 서명 설정이 필요합니다. 현재 생성된 `naymnaym-upload.jks`는 로컬 전용 파일이므로 분실하지 않도록 별도 보관해야 합니다.

## 정식 출시 전 Google Play 기준

새 개인 개발자 계정에서 프로덕션 접근을 신청하려면 비공개 테스트에서 12명 이상 테스터가 14일 연속 opt-in 상태를 유지해야 합니다. 단순 이메일 등록만으로 충분하다고 보지 말고, 각 테스터가 링크로 참여 수락, 설치, 핵심 흐름 확인, 간단한 피드백 제출까지 진행하도록 운영합니다.

현재 Android 테스트 앱은 심사 준비를 위해 다음 항목을 앱 안에서 직접 확인할 수 있습니다.

- 개인정보 처리방침, 데이터 안전 안내, 지원 안내 링크
- 데이터 관리 화면과 로컬 데이터 삭제
- 실제 학교/API 실패/급식 없음 상태에서 샘플 자동 표시 금지
- 체험 모드에서만 샘플 표시
- 알레르기 번호가 있는 메뉴의 한 입 도전 잠금
- 보호자 초대 링크 공유와 초대 코드 서버 등록
- 부모 공유 범위 제한: 먹은 정도, 한 입 도전 기록, 알레르기 주의만 공유하고 사진은 제외

Google Play 입력 초안과 테스트 운영 문서는 `release/GooglePlayMetadata/`에 둡니다.
