# Apps in Toss 콘솔 메타데이터

2026-09-05 Phase 4 콘솔 등록 결과와 로컬 release candidate 기준이다.

| 항목 | 값 |
|---|---|
| 기존 mini-app | 57196 업데이트 대상 |
| appName | `nyam-levelup` |
| 표시 이름 | `급식레벨업` |
| 진입 경로 | `/today` |
| 브랜드 색 | `#FF8A3D` |
| 권한 | 없음 |
| 공개 Origin | `https://nyam-levelup.apps.tossmini.com` |
| 비공개 Origin | `https://nyam-levelup.private-apps.tossmini.com` |
| 개인정보 처리방침 | `https://nyam.h19h19.com/privacy.html` |
| 문의 | `https://nyam.h19h19.com/support.html` |
| 현재 출시 버전 | `20260725-1` (SDK 2.10.7) |
| 새 테스트 버전 | `20260905-15` (SDK 3.3.0, 검토 필요) |
| test deployment ID | `01a06cfb-ab5f-705d-b1b6-815f815f6cb0` |
| test scheme | `intoss-private://nyam-levelup?_deploymentId=01a06cfb-ab5f-705d-b1b6-815f815f6cb0&host=appsInTossHost` |

콘솔에서 확인된 icon 원본 URL은 `https://static.toss.im/appsintoss/62825/97e8a73d-162e-4800-8904-42fc49e4af5d.png`이다. 저장본은 `console-icon.png`, 600×600 PNG, SHA-256 `72ac4fddcdf11063eba921554a2cf7c289cf33ad72d50b9615d7457a3c3d5b27`이다. URL 경로의 숫자는 mini-app 식별자로 추정하지 않는다.

SDK 3 config에는 콘솔이 관리하는 표시 이름과 icon을 중복 삽입하지 않는다. 새 번들은 기존 mini-app 57196에만 등록했고 콘솔의 `검토 요청`과 `출시하기`는 실행하지 않았다. QR은 발급됐지만 연결된 물리 iOS/Android 기기가 없어 실기기 결과는 아직 없다.
