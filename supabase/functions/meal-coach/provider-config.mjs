const DEFAULT_TTL_MS = 300_000;
const STALE_MS = 3_600_000;
const MAX_CONFIG_BYTES = 4096;
const CONFIG_TIMEOUT_MS = 3_000;

// Resolves the AI provider settings from a remote JSON document so the
// operator can rotate the provider key, switch model or endpoint, or turn the
// feature off without redeploying the edge function. The remote document is
// served from the operator's NAS behind an unguessable path and a shared
// token header; it is never exposed to app clients.
//
// Remote document shape:
//   { "enabled": true, "apiKey": "...", "endpoint": "https://...", "model": "..." }
// endpoint/model are optional and fall back to the built-in defaults.
// "enabled": false disables AI calls immediately (kill switch) without
// requiring a valid apiKey.
export function createRemoteProviderResolver({
  configUrl = '',
  configToken = '',
  fallback,
  fetcher = fetch,
  now = () => Date.now(),
  ttlMs = DEFAULT_TTL_MS,
}) {
  if (!fallback || typeof fallback.key !== 'string') throw new Error('invalid_configuration');
  let parsed = null;
  try {
    parsed = configUrl ? new URL(configUrl) : null;
  } catch {
    parsed = null;
  }
  const usable = parsed !== null && parsed.protocol === 'https:';
  let cache = null;
  return async () => {
    if (!usable) return { ...fallback, enabled: true };
    const instant = now();
    if (cache && instant - cache.at < ttlMs) return cache.value;
    try {
      const headers = {};
      if (configToken) headers['x-nyam-config-token'] = configToken;
      const res = await fetcher(parsed, {
        headers,
        redirect: 'error',
        signal: AbortSignal.timeout(CONFIG_TIMEOUT_MS),
      });
      if (!res.ok) throw new Error('config_unavailable');
      const text = await res.text();
      if (new TextEncoder().encode(text).byteLength > MAX_CONFIG_BYTES) throw new Error('config_too_large');
      const value = normalizeConfig(JSON.parse(text), fallback);
      cache = { value, at: instant };
      return value;
    } catch {
      if (cache && now() - cache.at < STALE_MS) return cache.value;
      return { ...fallback, enabled: true };
    }
  };
}

function normalizeConfig(raw, fallback) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid');
  if (raw.enabled === false) return { enabled: false, key: '', url: fallback.url, model: fallback.model };
  const key = typeof raw.apiKey === 'string' ? raw.apiKey.trim() : '';
  if (!key || key.length > 512 || /\s/.test(key)) throw new Error('invalid');
  let url = fallback.url;
  if (typeof raw.endpoint === 'string' && raw.endpoint.trim()) {
    const endpoint = raw.endpoint.trim();
    try {
      if (new URL(endpoint).protocol !== 'https:') throw new Error('invalid');
    } catch {
      throw new Error('invalid');
    }
    url = endpoint;
  }
  const model = typeof raw.model === 'string' && /^[a-z0-9][a-z0-9._/-]{0,79}$/i.test(raw.model.trim())
    ? raw.model.trim()
    : fallback.model;
  return { enabled: true, key, url, model };
}
