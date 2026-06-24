# 냠냠레벨업 출시 사이트

`dist/` 폴더는 App Store Connect에 입력할 개인정보 처리방침 URL, 지원 URL, 데이터 안전 안내 URL을 위한 정적 사이트 산출물이다.

## 배포 파일

- `dist/index.html`
- `dist/privacy.html`
- `dist/data-safety.html`
- `dist/support.html`
- `dist/assets/site.css`
- `dist/assets/*.png`

## App Store Connect URL

정적 호스팅 루트에 `dist/` 내용을 그대로 올린 뒤 아래 URL을 입력한다.

- 개인정보 처리방침 URL: `https://<배포도메인>/privacy.html`
- 데이터 안전 안내 URL: `https://<배포도메인>/data-safety.html`
- 지원 URL: `https://<배포도메인>/support.html`

## 검증

로컬에서 별도 빌드 없이 브라우저로 `dist/index.html`, `dist/privacy.html`, `dist/data-safety.html`, `dist/support.html`을 열어 확인할 수 있다. 배포 후에는 세 URL이 모두 HTTPS로 열리는지 확인한다.
