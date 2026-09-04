export function readClientEnv(env: Record<string, string | boolean | undefined> = import.meta.env) {
  const proxyUrl = env.VITE_NEIS_PROXY_URL;
  const clientToken = env.VITE_NEIS_CLIENT_TOKEN || env.VITE_SUPABASE_ANON_KEY;
  if (typeof proxyUrl !== 'string' || typeof clientToken !== 'string') {
    throw new Error('NEIS client environment is not configured.');
  }
  return { proxyUrl, clientToken };
}
