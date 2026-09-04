import { afterEach, describe, expect, it, vi } from 'vitest';
import { NeisClientError, clientErrorMessage, createNeisClient } from './neisClient';

afterEach(() => vi.unstubAllGlobals());

describe('NEIS client', () => {
  it('posts a text/plain envelope and returns range data', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ok: true, data: [] }) });
    vi.stubGlobal('fetch', fetchMock);
    const client = createNeisClient({ proxyUrl: 'https://proxy.example', clientToken: 'client-token' });
    await client.fetchMealsRange({ officeCode: 'B10', schoolCode: '123', fromDate: '20260901', toDate: '20260907' });
    expect(fetchMock).toHaveBeenCalledWith('https://proxy.example', expect.objectContaining({
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=UTF-8' },
    }));
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({
      clientToken: 'client-token',
      request: { action: 'fetchMealsRange', payload: { officeCode: 'B10', schoolCode: '123', fromDate: '20260901', toDate: '20260907' } },
    });
  });

  it('keeps proxy codes distinct and classifies fetch failures as network errors', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({ ok: false, code: 'RATE_LIMITED', message: 'slow' }) }));
    const client = createNeisClient({ proxyUrl: 'https://proxy.example', clientToken: 'token' });
    await expect(client.searchSchools('서울', 'elementary')).rejects.toMatchObject({ kind: 'RATE_LIMITED' });
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('offline')));
    await expect(client.searchSchools('서울', 'elementary')).rejects.toEqual(expect.objectContaining<Partial<NeisClientError>>({ kind: 'NETWORK' }));
  });

  it('gives origin, rate, backend, and network failures distinct user copy', () => {
    const messages = ['FORBIDDEN_ORIGIN', 'RATE_LIMITED', 'UPSTREAM_ERROR', 'NETWORK'].map((kind) => clientErrorMessage(new NeisClientError(kind as never, 'x')));
    expect(new Set(messages).size).toBe(4);
  });

  it.each([
    ['school search', (client: ReturnType<typeof createNeisClient>) => client.searchSchools('학교', 'middle'), [{ name: '필드 부족' }]],
    ['single meal', (client: ReturnType<typeof createNeisClient>) => client.fetchMeals({ officeCode: 'B10', schoolCode: '1', date: '20260904' }), { date: '20260904', menuItems: 'invalid' }],
    ['meal range', (client: ReturnType<typeof createNeisClient>) => client.fetchMealsRange({ officeCode: 'B10', schoolCode: '1', fromDate: '20260901', toDate: '20260907' }), [{ date: 'invalid' }]],
  ])('rejects malformed successful %s data before it reaches UI code', async (_name, call, data) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ok: true, data }) }));
    const client = createNeisClient({ proxyUrl: 'https://proxy.example', clientToken: 'token' });
    await expect(call(client)).rejects.toMatchObject({ kind: 'INVALID_RESPONSE' });
  });
});
