import { Storage } from '@apps-in-toss/web-framework';

export interface StoragePort {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  clearItems(): Promise<void>;
}

const browserFallback: StoragePort = {
  async getItem(key) { return window.localStorage.getItem(key); },
  async setItem(key, value) { window.localStorage.setItem(key, value); },
  async clearItems() { window.localStorage.clear(); },
};

export function getStorage(): StoragePort {
  if (import.meta.env.DEV && typeof window !== 'undefined' && !(window as unknown as { ReactNativeWebView?: unknown }).ReactNativeWebView) {
    return browserFallback;
  }
  return {
    getItem: Storage.getItem,
    setItem: Storage.setItem,
    clearItems: Storage.clearItems,
  };
}
