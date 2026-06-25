# 사진 기록 출시 증거

## 제출 정책

급식판 사진 기록은 1.0 포함 기능이다. 다만 App Store 업로드 스크린샷에는 실제 아이 사진, 친구 얼굴, 이름표, 반/번호가 들어갈 수 있으므로 사진 기록 화면을 별도 전면 스크린샷으로 넣지 않는다. 현재 6.9형 업로드 세트는 부모 요약의 공유 사진 맥락, 설정/지원의 개인정보 안내, 그리고 릴리스 게이트 테스트로 기능을 증명한다.

사진 기록 화면을 향후 App Store 전면에 추가하려면 실제 급식판이나 학생 정보가 보이지 않는 익명 샘플 자산만 사용한다.

## 앱 기능 증거

- `TodayMealView`는 급식판 사진 섹션에서 사진 선택, 사진 찍기, 사진 삭제를 제공한다.
- 사진은 기본적으로 기기 내부에 저장된다.
- 부모 사진 공유는 기록 공유가 켜져 있고 사진 공유 권한이 켜진 경우에만 가능하다.
- 기록 공유를 끄면 사진 공유도 해제된다.
- 화면 문구는 급식판만 찍고 친구 얼굴, 이름표, 반/번호가 나오지 않도록 안내한다.

## 테스트 증거

- `testLocalPhotoStoreSavesAndDeletesFile`: 로컬 사진 파일 저장/삭제
- `testUpdateMealPhotoSharingClearsChildLinkWhenDisabled`: 사진 공유 해제 시 부모 연결 제거
- `testChildSummariesOnlyExposeParentSharedPhotosAndRecords`: 부모 요약은 공유된 기록/사진만 노출
- `testCloudKitPhotoRecordRequiresBothPermissions`: CloudKit 사진 공유는 기록/사진 권한이 모두 필요
- `testCloudKitSharedPhotoRecordFieldsMatchConsoleRunbook`: CloudKit `SharedMealPhoto` 필드 계약 고정
- `testResetAllDataClearsProfileRecordsProgressParentLinksAndPhotoFiles`: 전체 데이터 삭제 시 사진 파일과 orphan 사진 삭제

## 릴리스 게이트

`scripts/verify-release-readiness.sh`는 사진 기록 UI 문구, Info.plist 사진/카메라 권한 문구, 사진 공유 테스트 이름, App Privacy의 `Photos or Videos` 입력 기준을 확인한다.
