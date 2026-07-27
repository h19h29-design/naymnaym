import { Storage } from '@apps-in-toss/web-framework';

export interface KeyValueStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

function localDevelopmentStorage(): KeyValueStorage | null {
  if (!import.meta.env.DEV || typeof window === 'undefined') return null;
  return {
    getItem: async (key) => window.localStorage.getItem(key),
    setItem: async (key, value) => window.localStorage.setItem(key, value),
    removeItem: async (key) => window.localStorage.removeItem(key),
  };
}

const fallback = localDevelopmentStorage();

export const tossStorage: KeyValueStorage = {
  getItem: async (key) => {
    try {
      return await Storage.getItem(key);
    } catch (error) {
      if (fallback !== null) return fallback.getItem(key);
      throw error;
    }
  },
  setItem: async (key, value) => {
    try {
      await Storage.setItem(key, value);
    } catch (error) {
      if (fallback !== null) return fallback.setItem(key, value);
      throw error;
    }
  },
  removeItem: async (key) => {
    try {
      await Storage.removeItem(key);
    } catch (error) {
      if (fallback !== null) return fallback.removeItem(key);
      throw error;
    }
  },
};
