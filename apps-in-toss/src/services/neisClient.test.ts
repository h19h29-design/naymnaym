import { afterEach, describe, expect, it, vi } from 'vitest';
import { NeisClientError, createNeisClient } from './neisClient';

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
});
