import type { ApiResult, MealDay, ProxyErrorCode, School, SchoolType } from '@nyam/neis-contract';

export type ClientErrorKind = ProxyErrorCode | 'NETWORK' | 'INVALID_RESPONSE';

export class NeisClientError extends Error {
  constructor(public readonly kind: ClientErrorKind, message: string) { super(message); }
}

export function clientErrorMessage(error: unknown) {
  const kind = error instanceof NeisClientError ? error.kind : 'NETWORK';
  if (kind === 'NOT_CONFIGURED' || kind === 'UPSTREAM_ERROR' || kind === 'INVALID_RESPONSE') return '급식 서버를 점검하고 있어요. 잠시 후 다시 시도해 주세요.';
  if (kind === 'FORBIDDEN_ORIGIN') return '허용된 토스 앱 환경에서 다시 열어 주세요.';
  if (kind === 'RATE_LIMITED') return '요청이 많아요. 잠시 쉬었다 다시 시도해 주세요.';
  return '네트워크 연결을 확인하고 다시 시도해 주세요.';
}

interface ClientConfig { proxyUrl: string; clientToken: string }

export function createNeisClient(config: ClientConfig) {
  async function request<T>(action: string, payload: object): Promise<T> {
    let response: Response;
    try {
      response = await fetch(config.proxyUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain;charset=UTF-8' },
        body: JSON.stringify({ clientToken: config.clientToken, request: { action, payload } }),
      });
    } catch {
      throw new NeisClientError('NETWORK', '네트워크 연결을 확인해 주세요.');
    }
    let result: ApiResult<T>;
    try { result = await response.json() as ApiResult<T>; }
    catch { throw new NeisClientError('INVALID_RESPONSE', '서버 응답을 확인할 수 없어요.'); }
    if (!result.ok) throw new NeisClientError(result.code, result.message);
    return result.data;
  }
  return {
    searchSchools(keyword: string, schoolType?: SchoolType) {
      return request<School[]>('searchSchools', { keyword, ...(schoolType ? { schoolType } : {}) });
    },
    fetchMeals(payload: { officeCode: string; schoolCode: string; date: string }) {
      return request<MealDay>('fetchMeals', payload);
    },
    fetchMealsRange(payload: { officeCode: string; schoolCode: string; fromDate: string; toDate: string }) {
      return request<MealDay[]>('fetchMealsRange', payload);
    },
  };
}
