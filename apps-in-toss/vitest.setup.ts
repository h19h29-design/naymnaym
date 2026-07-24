import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

vi.stubEnv('VITE_NEIS_PROXY_URL', 'https://edge.test/neis-proxy');
vi.stubEnv('VITE_SUPABASE_ANON_KEY', 'public-test-anon-key');
