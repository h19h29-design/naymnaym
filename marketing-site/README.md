# 급식레벨업 출시 사이트

`dist/` 폴더는 App Store Connect에 입력할 개인정보 처리방침 URL, 지원 URL, 데이터 안전 안내 URL을 위한 정적 사이트 산출물이다.

## 배포 파일

- `dist/index.html`
- `dist/privacy.html`
- `dist/data-safety.html`
- `dist/support.html`
- `dist/assets/site.css`
- `dist/assets/*.png`

## 스토어 등록 URL

운영 도메인에는 아래 URL을 사용한다.

- 홈페이지: `https://nyam.h19h19.com/`
- 개인정보 처리방침 URL: `https://nyam.h19h19.com/privacy.html`
- 데이터 안전 안내 URL: `https://nyam.h19h19.com/data-safety.html`
- 지원 URL: `https://nyam.h19h19.com/support.html`

## 검증

로컬에서 별도 빌드 없이 브라우저로 `dist/index.html`, `dist/privacy.html`, `dist/data-safety.html`, `dist/support.html`을 열어 확인할 수 있다. 배포 후에는 세 URL이 모두 HTTPS로 열리는지 확인한다.
