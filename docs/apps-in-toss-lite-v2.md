# Apps in Toss Lite v2 구현 결정

## 범위

Lite v2는 네 경로와 세 탭으로 제한했다. 오늘 화면이 급식·알레르기·식사 기록·성장을 한 흐름으로 묶고, 주간 화면은 `fetchMealsRange` 한 번으로 실제 7일을 표시한다. 보호자 연결, 계정, 사진, 공유, 알림, 광고, 분석, 월간과 도감은 제외했다.

## 계약

client는 `VITE_NEIS_PROXY_URL`만 교체하면 backend를 바꿀 수 있다. POST body는 `{clientToken, request}`이고 `text/plain;charset=UTF-8`로 전송한다. 학교는 elementary/middle/high를 모두 지원한다. range 날짜는 실제 YYYYMMDD 양 끝 포함 1~7일이며 반환되지 않은 날짜는 급식 없음이다.

화면은 live, 저장된 급식, 급식 없음, backend 점검, network, Origin 거부, rate limit을 구분한다. 실제 오류를 sample로 덮지 않는다. 사용자가 `체험 급식 보기`를 눌렀을 때만 sample이 나타나며 어떤 저장 함수도 호출하지 않는다.

## Storage와 XP

v2 envelope를 쓰기 전에 다섯 v1 key를 읽는다. 완료된 v2가 있으면 migration을 다시 하지 않아 idempotent하다. v2 또는 v1 JSON이 손상돼도 white screen 대신 유효 데이터만 복구한다. migration 성공 뒤에도 v1 key를 지우지 않는다.

legacy totalXp는 그대로 totalXP가 된다. legacy record의 기존 awardedXp는 baseline과 contribution으로 보존하며, 이후 같은 날짜·메뉴를 수정하면 그 identity의 최종 status contribution으로 교체한다. 신규 기록은 안 먹음 3, 한 입 도전 18, 잘 먹음 10 XP이고 하루 base cap은 50이다. 총 XP로 최신 12단계를 다시 선택한다.

알레르기 code는 숫자로 교차 확인한다. 위험 메뉴의 한 입 도전은 잠그고 “알레르기 가능성이 있어요. 학교 안내와 보호자 확인이 먼저예요.”를 표시한다.

## 에셋 ruling

main에서 검증된 캐릭터 원본은 7개뿐이었다. 이를 각각 512×512 WebP로 최적화해 총 약 220KB로 만들었다. 8~12단계는 level 7 이미지를 재사용하거나 새 그림을 만들지 않고 동일한 접근 가능 placeholder를 쓴다. 논리 threshold와 제목 12개는 유지한다.

## 운영 backend 비교

| 선택지 | 장점 | 위험/비용 | 이번 결정 |
|---|---|---|---|
| Supabase Free 유지 | 기존 구성 재사용 | inactivity 재발 가능 | 운영 의존에서 제외 |
| Supabase 유료 | 자동 중지 위험 감소 | 지속 비용과 승인 필요 | 생성·전환 안 함 |
| Vercel Function 등 상시 proxy | frontend 변경 작음 | 새 운영 리소스와 정책 필요 | 승인 전 생성 안 함 |
| 현재 NAS 전용 proxy | 이미 허용 Origin과 실제 NEIS 검증 완료 | NAS 운영 가용성 관리 필요 | 현재 endpoint |

가짜 heartbeat나 의미 없는 DB 호출은 추가하지 않았다.
