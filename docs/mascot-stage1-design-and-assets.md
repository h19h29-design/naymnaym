# 냠냠레벨업 마스코트 Stage 1 — 디자인·에셋·TTS 기준

이 문서는 1단계 마스코트 고도화의 소스 오브 트루스와 파일 위치를 정한다.

## 이번 단계 범위

- 기존 `MascotRigView` 기반 캐릭터의 반응 모션 유지/강화
- 급식 기록 후 캐릭터 말풍선 표시
- `AVSpeechSynthesizer` 기반 한국어 로컬 TTS
- TTS 재생 중 캐릭터에 작은 말하기 모션 적용
- 홈 화면에서 캐릭터를 더 큰 주인공 영역으로 배치
- 기존 숲/초록색 중심 UI에 인디고·코랄·하늘색·노랑·라벤더 포인트 추가
- AI 대사 생성은 다음 단계로 미룬다. 이번 단계에는 API 키나 외부 AI 호출을 넣지 않는다.

## 어디에 무엇을 보관할지

### Figma

Figma는 **UI 설계와 캐릭터 비주얼 기준**을 관리한다.

추천 페이지 구조:

- `00 Reference` — 현재 캐릭터 시트와 참고 이미지
- `01 Foundations` — 컬러, 타이포, 간격, radius
- `02 Components` — 버튼, 카드, 말풍선, XP, 배지
- `03 Child Home` — 캐릭터 중심 홈 화면
- `04 Meal Record` — 먹기/한입/오늘은 어려워요 상태
- `05 Character` — 캐릭터 포즈, 표정, 성장 단계
- `06 Dev Handoff` — 구현 기준 프레임과 주석

무료 Figma 플랜으로도 이번 단계의 일반적인 디자인 파일, 프레임, 컴포넌트, 캐릭터 레퍼런스 관리에는 충분하다. 다만 MCP/Dev 관련 자동화 호출량이나 고급 협업 기능은 플랜/좌석에 따라 제한될 수 있으므로, Figma 자동화를 프로젝트의 필수 런타임 의존성으로 두지 않는다.

### GitHub 저장소

앱에서 실제 사용하는 코드는 GitHub가 소스 오브 트루스다.

- 캐릭터 모션 코드: `NaymNaymLevelUp/Rebuild/Mascot/`
- 홈 캐릭터 UI: `NaymNaymLevelUp/Rebuild/Child/TodayForestView.swift`
- 디자인 토큰: `NaymNaymLevelUp/Rebuild/Foundation/RebuildDesignTokens.swift`
- 로컬 TTS: 현재 `MascotMotionController.swift`의 `MascotSpeechSynthesizer`
- 2D 앱 에셋: 기존 Asset Catalog/Resources 구조를 따른다.

Figma에서 확정한 컬러·크기·간격·컴포넌트 값은 구현 시 SwiftUI 디자인 토큰으로 옮긴다. Figma 자체가 앱 런타임 의존성이 되어서는 안 된다.

### 향후 3D 캐릭터

Figma는 3D 원본 제작 툴로 사용하지 않는다.

권장 파이프라인:

`캐릭터 시트/레퍼런스(Figma) -> Blender 원본(.blend) -> 리깅/애니메이션 -> USDZ -> RealityKit -> iOS 앱`

- `.blend` 같은 대형 바이너리 원본은 일반 Git 커밋보다 Git LFS 또는 팀용 Drive 보관을 권장한다.
- 앱에 포함되는 최종 `.usdz`와 필요한 텍스처는 저장소의 `Resources/Models` 같은 전용 폴더에 둔다.
- 최종 3D 파일이 커지면 Git LFS를 사용한다.
- 현재 Stage 1에서는 기존 2D rig를 실제 동작 구현에 사용하고, 3D 교체가 가능하도록 UI/TTS 로직을 캐릭터 렌더링과 분리한다.

## TTS 원칙

Stage 1 TTS는 Apple `AVSpeechSynthesizer`를 사용한다.

장점:

- API 키 없음
- 서버 비용 없음
- 네트워크가 없어도 기본 음성 사용 가능
- AI를 나중에 붙여도 `AI -> 텍스트 -> MascotSpeechSynthesizer` 구조를 그대로 유지 가능

TTS 음원 파일을 Figma나 Assets에 미리 저장할 필요는 없다. 대사는 문자열이며 기기에서 즉시 합성한다.

## 반응 UX 원칙

- `mealSuccess`: 밝은 반응 + 축하 모션 + 음성
- `comfort`: 실패/비난 표현 금지. “오늘은 여기까지 해도 괜찮아”처럼 재도전 친화적인 표현 사용
- 알레르기 회피 행동은 절대 먹도록 유도하지 않는다.
- 음성은 사용자가 끌 수 있고 설정값을 기기에 저장한다.
- 접근성의 `Reduce Motion`을 존중한다.

## 다음 단계

Stage 2에서 필요할 것:

1. 상태별 안전한 기본 대사 카탈로그
2. 메뉴명/도전 이력 기반 AI 개인화 대사
3. 서버측 AI 프록시와 키 보호
4. 아동용 생성 대사 안전 규칙
5. Blender 캐릭터 리깅과 `idle / wave / eat / cheer / comfort / levelUp` 애니메이션 클립
6. USDZ/RealityKit 렌더러를 기존 `MascotRigView` 자리에 교체 가능한 구조로 연결
