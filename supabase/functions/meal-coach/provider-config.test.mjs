import test from 'node:test';
import assert from 'node:assert/strict';
import { createRemoteProviderResolver } from './provider-config.mjs';

const fallback = { key: 'env-fallback-key', url: 'https://fallback.example/v1', model: 'fallback-model' };

function configResponse(body, status = 200) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

test('returns the static fallback when no remote config url is set', async () => {
  const resolve = createRemoteProviderResolver({ fallback });
  assert.deepEqual(await resolve(), { ...fallback, enabled: true });
});

test('rejects a non-https config url and falls back', async () => {
  let calls = 0;
  const resolve = createRemoteProviderResolver({
    configUrl: 'http://nyam.h19h19.com/config.json',
    fallback,
    fetcher: async () => { calls += 1; return configResponse({ apiKey: 'x' }); },
  });
  assert.deepEqual(await resolve(), { ...fallback, enabled: true });
  assert.equal(calls, 0);
});

test('remote config overrides key, model and endpoint and caches within the ttl', async () => {
  let calls = 0;
  const seen = [];
  const resolve = createRemoteProviderResolver({
    configUrl: 'https://nyam.h19h19.com/nyam-internal/abc.json',
    configToken: 'token-123',
    fallback,
    fetcher: async (url, init) => {
      calls += 1;
      seen.push({ url: String(url), token: init.headers['x-nyam-config-token'] });
      return configResponse({ enabled: true, apiKey: 'rotated-key', model: 'other-model', endpoint: 'https://provider.example/v2' });
    },
  });
  const first = await resolve();
  const second = await resolve();
  assert.equal(first.key, 'rotated-key');
  assert.equal(first.model, 'other-model');
  assert.equal(first.url, 'https://provider.example/v2');
  assert.equal(first.enabled, true);
  assert.equal(calls, 1, 'second resolve should be served from cache');
  assert.equal(seen[0].token, 'token-123');
});

test('enabled false acts as a kill switch even without a key', async () => {
  const resolve = createRemoteProviderResolver({
    configUrl: 'https://nyam.h19h19.com/nyam-internal/abc.json',
    fallback,
    fetcher: async () => configResponse({ enabled: false }),
  });
  const value = await resolve();
  assert.equal(value.enabled, false);
});

test('falls back to the env key when the remote config is unreachable', async () => {
  const resolve = createRemoteProviderResolver({
    configUrl: 'https://nyam.h19h19.com/nyam-internal/abc.json',
    fallback,
    fetcher: async () => { throw new Error('network_down'); },
  });
  assert.deepEqual(await resolve(), { ...fallback, enabled: true });
});

test('serves the last good config when a refresh fails inside the stale window', async () => {
  let clock = 0;
  let fail = false;
  const resolve = createRemoteProviderResolver({
    configUrl: 'https://nyam.h19h19.com/nyam-internal/abc.json',
    fallback,
    now: () => clock,
    ttlMs: 100,
    fetcher: async () => {
      if (fail) throw new Error('nas_offline');
      return configResponse({ apiKey: 'rotated-key' });
    },
  });
  assert.equal((await resolve()).key, 'rotated-key');
  clock += 200;
  fail = true;
  assert.equal((await resolve()).key, 'rotated-key', 'stale cache should survive a failed refresh');
});

test('rejects malformed or hostile config payloads', async () => {
  for (const body of ['not json', { apiKey: '' }, { apiKey: 'has space' }, { apiKey: 'k', endpoint: 'http://insecure.example' }, ['array']]) {
    const resolve = createRemoteProviderResolver({
      configUrl: 'https://nyam.h19h19.com/nyam-internal/abc.json',
      fallback,
      fetcher: async () => configResponse(body),
    });
    assert.deepEqual(await resolve(), { ...fallback, enabled: true });
  }
});
