import type {
  ApiResult,
  MealDay,
  ProxyErrorCode,
  ProxyRequest,
  School,
  SchoolType,
} from '@nyam/neis-contract';
import { clientEnv } from '../config/clientEnv';

interface NeisClientOptions {
  endpoint: string;
  anonKey: string;
  fetch?: typeof fetch;
}

const PROXY_ERROR_CODES = new Set<ProxyErrorCode>([
  'BAD_REQUEST',
  'FORBIDDEN_ORIGIN',
  'NO_DATA',
  'NOT_CONFIGURED',
  'RATE_LIMITED',
  'UPSTREAM_ERROR',
]);

function isApiResult(value: unknown): value is ApiResult<unknown> {
  if (typeof value !== 'object' || value === null || !('ok' in value)) return false;
  if (value.ok === true) return 'data' in value;
  return value.ok === false
    && 'code' in value
    && typeof value.code === 'string'
    && PROXY_ERROR_CODES.has(value.code as ProxyErrorCode)
    && 'message' in value
    && typeof value.message === 'string';
}

export class NeisClientError extends Error {
  constructor(
    public readonly code: ProxyErrorCode,
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = 'NeisClientError';
  }
}

export class NeisClient {
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: NeisClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
  }

  searchSchools(
    keyword: string,
    schoolType: SchoolType,
    signal?: AbortSignal,
  ): Promise<School[]> {
    return this.post({
      action: 'searchSchools',
      payload: { keyword, schoolType },
    }, signal);
  }

  fetchMeal(school: School, date: string, signal?: AbortSignal): Promise<MealDay> {
    return this.post({
      action: 'fetchMeals',
      payload: {
        officeCode: school.officeCode,
        schoolCode: school.schoolCode,
        date,
      },
    }, signal);
  }

  private async post<T>(request: ProxyRequest, signal?: AbortSignal): Promise<T> {
    let response: Response;
    try {
      response = await this.fetchImpl(this.options.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          apikey: this.options.anonKey,
          authorization: `Bearer ${this.options.anonKey}`,
        },
        body: JSON.stringify(request),
        signal,
      });
    } catch (caught) {
      if (caught instanceof DOMException && caught.name === 'AbortError') throw caught;
      throw new NeisClientError(
        'UPSTREAM_ERROR',
        '급식 정보를 불러오지 못했어요.',
        0,
      );
    }

    let result: unknown;
    try {
      result = await response.json();
    } catch {
      throw this.unreadableResponse(response.status);
    }

    if (!isApiResult(result)) {
      throw this.unreadableResponse(response.status);
    }

    if (!result.ok) {
      throw new NeisClientError(result.code, result.message, response.status);
    }

    if (!response.ok) {
      throw this.unreadableResponse(response.status);
    }

    return result.data as T;
  }

  private unreadableResponse(status: number): NeisClientError {
    const rateLimited = status === 429;
    return new NeisClientError(
      rateLimited ? 'RATE_LIMITED' : 'UPSTREAM_ERROR',
      rateLimited
        ? '요청이 많아요. 잠시 후 다시 시도해 주세요.'
        : '급식 정보를 불러오지 못했어요.',
      status,
    );
  }
}

export const neisClient = new NeisClient({
  endpoint: clientEnv.neisProxyUrl,
  anonKey: clientEnv.supabaseAnonKey,
});
