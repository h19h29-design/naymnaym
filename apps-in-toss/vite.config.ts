import { loadEnv } from 'vite';
import { configDefaults, defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  if (mode === 'production' && (!env.VITE_NEIS_PROXY_URL || !(env.VITE_NEIS_CLIENT_TOKEN || env.VITE_SUPABASE_ANON_KEY))) {
    throw new Error('Production requires VITE_NEIS_PROXY_URL and VITE_NEIS_CLIENT_TOKEN.');
  }
  return {
    plugins: [react()],
    build: { sourcemap: false },
    test: {
      environment: 'jsdom',
      setupFiles: './vitest.setup.ts',
      clearMocks: true,
      exclude: [...configDefaults.exclude, 'scripts/**'],
    },
  };
});
