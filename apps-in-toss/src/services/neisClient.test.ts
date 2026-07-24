import type { ApiResult, MealDay, School } from '@nyam/neis-contract';
import { describe, expect, it, vi } from 'vitest';
import { school } from '../test/fixtures';
import { NeisClient } from './neisClient';

function makeClientReturning<T>(result: ApiResult<T>) {
  return new NeisClient({
    endpoint: 'https://edge.example/neis-proxy',
    anonKey: 'public-anon-key',
    fetch: async () => new Response(JSON.stringify(result), { status: result.ok ? 200 : 429 }),
  });
}

describe('NeisClient', () => {
  it('sends only the allowed action and anon authorization headers', async () => {
    const fetchSpy = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ ok: true, data: [] }), { status: 200 }));
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: fetchSpy,
    });

    await client.searchSchools('가람');

    const [, init] = fetchSpy.mock.calls[0];
    expect(init?.headers).toMatchObject({
      apikey: 'public-anon-key',
      authorization: 'Bearer public-anon-key',
    });
    expect(JSON.parse(String(init?.body))).toEqual({
      action: 'searchSchools',
      payload: { keyword: '가람' },
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
      action: 'fetchMeals',
      payload: {
        officeCode: school.officeCode,
        schoolCode: school.schoolCode,
        date: '20260724',
      },
    });
  });

  it('maps a stable edge error without entering demo mode', async () => {
    const client = makeClientReturning<MealDay>({
      ok: false, code: 'RATE_LIMITED', message: '잠시 후 다시 시도해 주세요.',
    });

    await expect(client.fetchMeal(school, '20260724'))
      .rejects.toMatchObject({ code: 'RATE_LIMITED' });
  });

  it('rejects malformed successful responses as an upstream error', async () => {
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: async () => new Response(JSON.stringify({ unexpected: true }), { status: 200 }),
    });

    await expect(client.searchSchools('가람'))
      .rejects.toMatchObject({ code: 'UPSTREAM_ERROR', status: 200 });
  });

  it('preserves aborts instead of converting them to an edge error', async () => {
    const client = new NeisClient({
      endpoint: 'https://edge.example/neis-proxy',
      anonKey: 'public-anon-key',
      fetch: async () => { throw new DOMException('Aborted', 'AbortError'); },
    });

    await expect(client.searchSchools('가람')).rejects.toMatchObject({ name: 'AbortError' });
  });
});
