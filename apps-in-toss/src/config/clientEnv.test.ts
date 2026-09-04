import { describe, expect, it } from 'vitest';
import { readClientEnv } from './clientEnv';

describe('client environment', () => {
  it('prefers the v2 client token and permits only the one-version legacy fallback', () => {
    expect(readClientEnv({ VITE_NEIS_PROXY_URL: 'https://proxy', VITE_NEIS_CLIENT_TOKEN: 'v2', VITE_SUPABASE_ANON_KEY: 'legacy' }).clientToken).toBe('v2');
    expect(readClientEnv({ VITE_NEIS_PROXY_URL: 'https://proxy', VITE_SUPABASE_ANON_KEY: 'legacy' }).clientToken).toBe('legacy');
    expect(() => readClientEnv({ VITE_NEIS_PROXY_URL: 'https://proxy' })).toThrow('not configured');
  });
});
