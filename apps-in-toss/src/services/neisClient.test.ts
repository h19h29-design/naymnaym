import type { ApiResult, MealDay, School } from '@nyam/neis-contract';
import { describe, expect, it, vi } from 'vitest';
import { school } from '../test/fixtures';
import { NeisClient } from './neisClient';

function makeClientReturning<T>(
  result: ApiResult<T>,
  status = result.ok ? 200 : 429,
) {
  return new NeisClient({
    endpoint: 'https://edge.example/neis-proxy',
    anonKey: 'public-anon-key',
    fetch: async () => new Response(JSON.stringify(result), { status }),
  });
}

describe('NeisClient', () => {
  it('uses a CORS-safelisted request so iOS WebView does not require preflight', async () => {
    const fetchSpy = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ ok: true, data: [] }), { status: 200 }));
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: fetchSpy,
    });

    await client.searchSchools('가람', 'middle');

    const [, init] = fetchSpy.mock.calls[0];
    expect(init?.headers).toEqual({
      'content-type': 'text/plain;charset=UTF-8',
    });
    expect(JSON.parse(String(init?.body))).toEqual({
      clientToken: 'public-anon-key',
      request: {
        action: 'searchSchools',
        payload: { keyword: '가람', schoolType: 'middle' },
      },
    });
  });

  it('sends a school identity and date when fetching a meal', async () => {
    const fetchSpy = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ ok: true, data: {} }), { status: 200 }));
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: fetchSpy,
    });

    await client.fetchMeal(school, '20260724');

    const [, init] = fetchSpy.mock.calls[0];
    expect(JSON.parse(String(init?.body))).toEqual({
      clientToken: 'public-anon-key',
      request: {
        action: 'fetchMeals',
        payload: {
          officeCode: school.officeCode,
          schoolCode: school.schoolCode,
          date: '20260724',
        },
      },
    });
  });

  it('passes an abort signal through a meal request', async () => {
    const fetchSpy = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ ok: true, data: {} }), { status: 200 }));
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: fetchSpy,
    });
    const controller = new AbortController();

    await client.fetchMeal(school, '20260724', controller.signal);

    expect(fetchSpy.mock.calls[0][1]?.signal).toBe(controller.signal);
  });

  it('maps a stable edge error without entering demo mode', async () => {
    const client = makeClientReturning<MealDay>({
      ok: false, code: 'RATE_LIMITED', message: '잠시 후 다시 시도해 주세요.',
    });

    await expect(client.fetchMeal(school, '20260724'))
      .rejects.toMatchObject({ code: 'RATE_LIMITED' });
  });

  it('preserves a validated NO_DATA edge error returned with HTTP 404', async () => {
    const client = makeClientReturning<MealDay>({
      ok: false,
      code: 'NO_DATA',
      message: '해당 날짜의 급식 정보가 없어요.',
    }, 404);

    await expect(client.fetchMeal(school, '20260724')).rejects.toMatchObject({
      code: 'NO_DATA',
      message: '해당 날짜의 급식 정보가 없어요.',
      status: 404,
    });
  });

  it('preserves another validated non-429 edge error and its status', async () => {
    const client = makeClientReturning<School[]>({
      ok: false,
      code: 'FORBIDDEN_ORIGIN',
      message: '허용되지 않은 요청이에요.',
    }, 403);

    await expect(client.searchSchools('가람', 'middle')).rejects.toMatchObject({
      code: 'FORBIDDEN_ORIGIN',
      message: '허용되지 않은 요청이에요.',
      status: 403,
    });
  });

  it('does not trust an unknown edge error code', async () => {
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: async () => new Response(JSON.stringify({
        ok: false,
        code: 'UNEXPECTED_CODE',
        message: '알 수 없는 오류',
      }), { status: 404 }),
    });

    await expect(client.searchSchools('가람', 'middle')).rejects.toMatchObject({
      code: 'UPSTREAM_ERROR',
      status: 404,
    });
  });

  it('rejects malformed successful responses as an upstream error', async () => {
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: async () => new Response(JSON.stringify({ unexpected: true }), { status: 200 }),
    });

    await expect(client.searchSchools('가람', 'middle'))
      .rejects.toMatchObject({ code: 'UPSTREAM_ERROR', status: 200 });
  });

  it('preserves aborts instead of converting them to an edge error', async () => {
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: async () => { throw new DOMException('Aborted', 'AbortError'); },
    });

    await expect(client.searchSchools('가람', 'middle'))
      .rejects.toMatchObject({ name: 'AbortError' });
  });
});
