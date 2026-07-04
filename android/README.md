# 냠냠레벨업 Android 테스트 앱

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
