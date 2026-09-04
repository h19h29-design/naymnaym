import type { MealDay, MealItem, ProxyErrorCode, School, SchoolType } from '@nyam/neis-contract';

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

const proxyErrorCodes = new Set<ProxyErrorCode>(['BAD_REQUEST', 'FORBIDDEN_ORIGIN', 'NO_DATA', 'NOT_CONFIGURED', 'RATE_LIMITED', 'UPSTREAM_ERROR']);

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

function isSchool(value: unknown): value is School {
  return isObject(value)
    && ['name', 'officeCode', 'schoolCode', 'region', 'address'].every((key) => typeof value[key] === 'string')
    && (value.schoolType === 'elementary' || value.schoolType === 'middle' || value.schoolType === 'high');
}

function isMealItem(value: unknown): value is MealItem {
  return isObject(value)
    && typeof value.id === 'string'
    && typeof value.name === 'string'
    && Array.isArray(value.allergyCodes)
    && value.allergyCodes.every((code) => Number.isInteger(code))
    && isStringArray(value.nutrients)
    && isStringArray(value.tags)
    && typeof value.sourceRawText === 'string';
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

function isMealDay(value: unknown): value is MealDay {
  return isObject(value)
    && typeof value.date === 'string'
    && /^\d{8}$/.test(value.date)
    && Array.isArray(value.menuItems)
    && value.menuItems.every(isMealItem)
    && isNullableString(value.calorie)
    && isNullableString(value.nutrition)
    && value.isSample === false
    && isNullableString(value.notice);
}

function isArrayOf<T>(itemGuard: (value: unknown) => value is T) {
  return (value: unknown): value is T[] => Array.isArray(value) && value.every(itemGuard);
}

export function createNeisClient(config: ClientConfig) {
  async function request<T>(action: string, payload: object, dataGuard: (value: unknown) => value is T): Promise<T> {
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
    let result: unknown;
    try { result = await response.json() as unknown; }
    catch { throw new NeisClientError('INVALID_RESPONSE', '서버 응답을 확인할 수 없어요.'); }
    if (!isObject(result) || typeof result.ok !== 'boolean') throw new NeisClientError('INVALID_RESPONSE', '서버 응답 형식이 올바르지 않아요.');
    if (!result.ok) {
      if (typeof result.code !== 'string' || !proxyErrorCodes.has(result.code as ProxyErrorCode) || typeof result.message !== 'string') {
        throw new NeisClientError('INVALID_RESPONSE', '서버 응답 형식이 올바르지 않아요.');
      }
      throw new NeisClientError(result.code as ProxyErrorCode, result.message);
    }
    if (!dataGuard(result.data)) throw new NeisClientError('INVALID_RESPONSE', '서버 응답 형식이 올바르지 않아요.');
    return result.data;
  }
  return {
    searchSchools(keyword: string, schoolType?: SchoolType) {
      return request('searchSchools', { keyword, ...(schoolType ? { schoolType } : {}) }, isArrayOf(isSchool));
    },
    fetchMeals(payload: { officeCode: string; schoolCode: string; date: string }) {
      return request('fetchMeals', payload, isMealDay);
    },
    fetchMealsRange(payload: { officeCode: string; schoolCode: string; fromDate: string; toDate: string }) {
      return request('fetchMealsRange', payload, isArrayOf(isMealDay));
    },
  };
}
