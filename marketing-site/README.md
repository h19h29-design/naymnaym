# 냠냠레벨업 Marketing Site

냠냠레벨업 iPhone 앱 홍보용 반응형 웹페이지입니다. 기존 Swift/iOS 프로젝트와 분리되도록 `marketing-site` 폴더 안에만 구성했습니다.

## 포함 섹션

- 앱 소개와 히어로
- 주요 기능
- 앱 화면 미리보기
- 레벨업 & 캐릭터
- 활용 공공데이터
- 개인정보 보호 원칙
- 출시 안내
- FAQ
- 푸터 문의/지원

## 기술 스택

- Vite
- React
- TypeScript
- Tailwind CSS v4 Vite 플러그인
- Lucide React 아이콘

## 실행

```bash
cd marketing-site
npm install
npm run dev
```

기본 개발 서버는 `http://127.0.0.1:5173`에서 실행됩니다.

## 빌드

```bash
cd marketing-site
npm run build
```

빌드 산출물은 `marketing-site/dist`에 생성됩니다.

## 자산 교체

현재 `public/assets`의 캐릭터 이미지는 첨부된 레퍼런스 이미지에서 필요한 일부만 잘라 사용했습니다. 실제 앱 스크린샷이나 최종 캐릭터 PNG가 준비되면 같은 경로의 파일을 교체하거나 `src/App.tsx`의 이미지 URL만 바꾸면 됩니다.

## 참고 문서

- Vite Getting Started: https://vite.dev/guide/
- Vite Production Build: https://vite.dev/guide/build
- Tailwind CSS with Vite: https://tailwindcss.com/docs
- Lucide React: https://lucide.dev/guide/react
