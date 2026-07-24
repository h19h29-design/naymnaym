import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

vi.stubEnv('VITE_NEIS_PROXY_URL', 'https://edge.test/neis-proxy');
vi.stubEnv('VITE_SUPABASE_ANON_KEY', 'public-test-anon-key');

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((media: string) => ({
    matches: false,
    media,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

Object.assign(window, {
  _uf: { _uf2: () => 'afterbegin' },
});

const insertAdjacentElement = HTMLElement.prototype.insertAdjacentElement;
HTMLElement.prototype.insertAdjacentElement = function (position, element) {
  const normalized = position === 'beforebegin'
    || position === 'afterbegin'
    || position === 'beforeend'
    || position === 'afterend'
    ? position
    : 'afterbegin';
  return insertAdjacentElement.call(this, normalized, element);
};
