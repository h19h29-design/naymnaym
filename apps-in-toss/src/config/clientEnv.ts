/// <reference types="vite/client" />

function required(name: string, value: string | undefined): string {
  const normalized = value?.trim();
  if (!normalized) throw new Error(`Missing required environment variable: ${name}`);
  return normalized;
}

export const clientEnv = {
  neisProxyUrl: required('VITE_NEIS_PROXY_URL', import.meta.env.VITE_NEIS_PROXY_URL),
  supabaseAnonKey: required(
    'VITE_SUPABASE_ANON_KEY',
    import.meta.env.VITE_SUPABASE_ANON_KEY,
  ),
} as const;
