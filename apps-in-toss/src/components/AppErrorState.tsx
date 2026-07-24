import { Button } from '@toss/tds-mobile';

const ERROR_COPY: Record<string, string> = {
  RATE_LIMITED: '요청이 많아 잠시 이용하기 어려워요. 조금 뒤 다시 시도해 주세요.',
  NOT_CONFIGURED: '급식 조회 준비 중이에요. 문의 및 지원에서 알려 주세요.',
  UPSTREAM_ERROR: '급식 정보를 불러오지 못했어요. 네트워크를 확인해 주세요.',
  PROFILE_REQUIRED: '먼저 학교를 설정해 주세요.',
};

export function AppErrorState({ code, retry }: { code: string; retry(): void }) {
  return (
    <section role="alert">
      <h2>급식 정보를 불러오지 못했어요</h2>
      <p>{ERROR_COPY[code] ?? ERROR_COPY.UPSTREAM_ERROR}</p>
      <Button onClick={retry}>다시 시도</Button>
    </section>
  );
}
