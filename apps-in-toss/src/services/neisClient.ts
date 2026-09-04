import type { ApiResult, MealDay, ProxyErrorCode, School, SchoolType } from '@nyam/neis-contract';

export type ClientErrorKind = ProxyErrorCode | 'NETWORK' | 'INVALID_RESPONSE';

export class NeisClientError extends Error {
  constructor(public readonly kind: ClientErrorKind, message: string) { super(message); }
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
