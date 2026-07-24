import { describe, expect, it } from 'vitest';
import { requireEnv } from './env';

describe('requireEnv', () => {
  it('returns a non-empty configured value', () => {
    expect(requireEnv('AIT_APP_NAME', { AIT_APP_NAME: 'nyam' })).toBe('nyam');
  });

  it('fails before a bundle can be built with missing console values', () => {
    expect(() => requireEnv('AIT_APP_NAME', { AIT_APP_NAME: '  ' }))
      .toThrow('Missing required environment variable: AIT_APP_NAME');
  });
});
