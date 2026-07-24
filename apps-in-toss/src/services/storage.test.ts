import { describe, expect, it } from 'vitest';
import type { KeyValueStorage } from './storage';

describe('KeyValueStorage', () => {
  it('supports the asynchronous key-value contract used by repositories', () => {
    const storage: KeyValueStorage = {
      getItem: async () => null,
      setItem: async () => undefined,
      removeItem: async () => undefined,
    };

    expect(storage).toBeDefined();
  });
});
