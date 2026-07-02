# 사진 기록 출시 증거

## 제출 정책

급식판 사진 기록은 1.0 포함 기능이다. 다만 App Store 업로드 스크린샷에는 실제 아이 사진, 친구 얼굴, 이름표, 반/번호가 들어갈 수 있으므로 사진 기록 화면을 별도 전면 스크린샷으로 넣지 않는다. 현재 6.9형 업로드 세트는 설정/지원의 개인정보 안내와 릴리스 게이트 테스트로 기능을 증명한다.

사진 기록 화면을 향후 App Store 전면에 추가하려면 실제 급식판이나 학생 정보가 보이지 않는 익명 샘플 자산만 사용한다.

## 앱 기능 증거

- `TodayMealView`는 급식판 사진 섹션에서 사진 선택, 사진 찍기, 사진 삭제를 제공한다.
- 사진은 기본적으로 기기 내부에 저장된다.
- 사진은 부모 공유 대상이 아니며 서버 부모 동기화에 포함하지 않는다.
- 부모 공유를 켜도 사진 메타데이터와 원본은 부모 화면에 노출하지 않는다.
- 화면 문구는 급식판만 찍고 친구 얼굴, 이름표, 반/번호가 나오지 않도록 안내한다.

## 테스트 증거

- `testLocalPhotoStoreSavesAndDeletesFile`: 로컬 사진 파일 저장/삭제
- `testMealPhotoSharingRemainsLocalOnly`: 사진 공유 요청이 들어와도 로컬 전용 상태 유지
- `testCloudKitPhotoRecordIsDisabled`: CloudKit 사진 레코드 생성 비활성화
- `testCloudKitSharedPhotoRecordNeverBuildsAsset`: CloudKit 사진 asset 생성 비활성화
- `testResetAllDataClearsProfileRecordsProgressParentLinksAndPhotoFiles`: 전체 데이터 삭제 시 사진 파일과 orphan 사진 삭제

## 릴리스 게이트

`scripts/verify-release-readiness.sh`는 사진 기록 UI 문구, Info.plist 사진/카메라 권한 문구, 부모 사진 공유 토글 부재, App Privacy의 로컬 전용 사진 기준을 확인한다.
