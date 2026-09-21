import test from 'node:test';
import assert from 'node:assert/strict';

async function loadHandler() {
  const module = await import('./handler.mjs').catch(() => null);
  assert.ok(module?.createMealCoachHandler, 'meal-coach handler implementation is missing');
  return module.createMealCoachHandler;
}

const payload = {
  requestId: '11111111-1111-4111-8111-111111111111',
  sessionId: '22222222-2222-4222-8222-222222222222',
  items: [
    { id: 'm0', nutrients: ['carbohydrate'] },
    { id: 'm1', nutrients: ['protein', 'iron'] },
  ],
  wholeMeal: { protein: 24, carbs: 87, fat: 18 },
};

const providerEnvelope = {
  choices: [{
    finish_reason: 'stop',
    message: {
      content: JSON.stringify({
        summary: '오늘 식단에서 여러 대표 영양소를 살펴봤어.',
        benefit: '탄수화물은 활동에 쓰이는 에너지원이고 단백질은 몸을 이루는 재료야.',
        highlights: [{ itemId: 'm1', nutrient: 'protein', reason: '몸을 이루는 재료로 쓰여.' }],
        caution: '메뉴를 바탕으로 살펴본 정보라 실제 먹은 양은 알 수 없어.',
        tip: '다음 식사에서도 다양한 음식을 부담 없이 만나 보자.',
      }),
    },
  }],
};

function request(body = payload) {
  return new Request('https://example.supabase.co/functions/v1/meal-coach', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test('valid anonymous meal payload returns a grounded AI review and records success', async () => {
  const createMealCoachHandler = await loadHandler();
  const claims = [];
  const finishes = [];
  const providerBodies = [];
  const providerHeaders = [];
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    now: () => new Date('2026-09-13T03:00:00.000Z'),
    claim: async (value) => { claims.push(value); return 'claimed'; },
    finish: async (value) => { finishes.push(value); },
    fetcher: async (_url, init) => {
      providerBodies.push(JSON.parse(init.body));
      providerHeaders.push(init.headers);
      return Response.json(providerEnvelope);
    },
  });

  const response = await handler(request());
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(
    Object.keys(body).sort(),
    ['benefit', 'caution', 'day', 'generatedAt', 'highlights', 'model', 'policyVersion', 'reviewId', 'source', 'summary', 'tip'].sort(),
  );
  assert.equal(body.source, 'ai');
  assert.equal(body.reviewId, payload.requestId);
  assert.equal(body.day, '2026-09-13');
  assert.equal(body.model, 'deepseek-v4.1-flash');
  assert.equal(claims.length, 1);
  assert.equal(finishes.length, 1);
  assert.equal(finishes[0].success, true);
  const forwarded = JSON.stringify(providerBodies[0]);
  assert.deepEqual(providerBodies[0].thinking, { type: 'disabled' });
  assert.equal(forwarded.includes('현미밥'), false);
  assert.equal(forwarded.includes('학교'), false);
  assert.equal(forwarded.includes(payload.sessionId), false);
  assert.equal(providerHeaders[0]['x-opencode-session'], claims[0].fingerprint);
  assert.equal(providerHeaders[0]['x-opencode-session'].includes(payload.sessionId), false);
});

test('normalizes the provider alternate highlight keys without accepting extra fields', async () => {
  const createMealCoachHandler = await loadHandler();
  const aliasEnvelope = structuredClone(providerEnvelope);
  aliasEnvelope.choices[0].message.content = JSON.stringify({
    summary: '오늘 식단의 대표 영양소를 살펴봤어.',
    benefit: '탄수화물은 활동 에너지에, 단백질은 몸을 이루는 데 쓰여.',
    highlights: [{ id: 'm1', nutrient: 'protein', role: '몸을 이루는 재료로 쓰여.' }],
    caution: '메뉴를 바탕으로 살펴본 참고 안내야.',
    tip: '다른 식사에서도 다양한 음식을 부담 없이 만나 보자.',
  });
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async () => Response.json(aliasEnvelope),
  });

  const response = await handler(request({ ...payload, requestId: '33333333-3333-4333-8333-333333333333' }));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).highlights, [
    { itemId: 'm1', nutrient: 'protein', reason: '몸을 이루는 재료로 쓰여.' },
  ]);
});

test('deduplicates multiple nutrient highlights for the same anonymous menu item', async () => {
  const createMealCoachHandler = await loadHandler();
  const duplicateEnvelope = structuredClone(providerEnvelope);
  duplicateEnvelope.choices[0].message.content = JSON.stringify({
    summary: '오늘 식단의 대표 영양소를 살펴봤어.',
    benefit: '단백질과 철분은 몸에서 서로 다른 역할을 해.',
    highlights: [
      { itemId: 'm1', nutrient: 'protein', reason: '몸을 이루는 재료로 쓰여.' },
      { itemId: 'm1', nutrient: 'iron', reason: '산소 운반에 관여하는 영양소야.' },
    ],
    caution: '메뉴를 바탕으로 살펴본 참고 안내야.',
    tip: '다른 식사에서도 다양한 음식을 부담 없이 만나 보자.',
  });
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async () => Response.json(duplicateEnvelope),
  });

  const response = await handler(request({ ...payload, requestId: '44444444-4444-4444-8444-444444444444' }));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).highlights, [
    { itemId: 'm1', nutrient: 'protein', reason: '몸을 이루는 재료로 쓰여.' },
  ]);
});

test('daily-used claim blocks a second provider request', async () => {
  const createMealCoachHandler = await loadHandler();
  let providerCalls = 0;
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'daily_used',
    finish: async () => assert.fail('finish must not run'),
    fetcher: async () => { providerCalls += 1; return Response.json(providerEnvelope); },
  });

  const response = await handler(request());
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: 'daily_used' });
  assert.equal(providerCalls, 0);
});

test('extra personal fields are rejected before quota or provider use', async () => {
  const createMealCoachHandler = await loadHandler();
  let claims = 0;
  let providerCalls = 0;
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => { claims += 1; return 'claimed'; },
    finish: async () => {},
    fetcher: async () => { providerCalls += 1; return Response.json(providerEnvelope); },
  });

  const response = await handler(request({ ...payload, schoolName: '테스트학교' }));
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: 'invalid_request' });
  assert.equal(claims, 0);
  assert.equal(providerCalls, 0);
});

test('missing server provider key fails without consuming daily quota', async () => {
  const createMealCoachHandler = await loadHandler();
  let claims = 0;
  const handler = createMealCoachHandler({
    providerKey: '',
    claim: async () => { claims += 1; return 'claimed'; },
    finish: async () => {},
    fetcher: async () => assert.fail('provider must not run'),
  });

  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'not_configured' });
  assert.equal(claims, 0);
});

const namedPayload = {
  requestId: '55555555-5555-4555-8555-555555555555',
  sessionId: '22222222-2222-4222-8222-222222222222',
  items: [
    { id: 'm0', name: '현미밥', nutrients: ['carbohydrate'] },
    { id: 'm1', name: '닭갈비', nutrients: ['protein', 'iron'] },
  ],
  wholeMeal: { protein: 24, carbs: 87, fat: 18 },
};

const namedEnvelope = {
  choices: [{
    finish_reason: 'stop',
    message: {
      content: JSON.stringify({
        summary: '오늘은 에너지를 주는 밥과 몸을 만드는 반찬이 함께 나왔어.',
        menus: [
          { itemId: 'm1', nutrient: 'protein', taste: '매콤달콤하고 쫄깃해.', role: '단백질은 몸을 만드는 재료야.', point: '채소와 함께 먹으면 더 맛있어.' },
          { itemId: 'm0', nutrient: 'carbohydrate', taste: '고소하고 쫀득한 밥이야.', role: '탄수화물은 몸을 움직이는 에너지원이야.', point: '천천히 씹어 먹으면 더 고소해.' },
        ],
        caution: '메뉴를 바탕으로 살펴본 추정이라 실제 먹은 양은 알 수 없어.',
        tip: '남긴 반찬의 영양소는 다음 식사에서 다양한 음식으로 만나 보자.',
      }),
    },
  }],
};

test('named menu items produce a per-menu v2 review sorted by request order', async () => {
  const createMealCoachHandler = await loadHandler();
  const providerBodies = [];
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    now: () => new Date('2026-09-16T03:00:00.000Z'),
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async (_url, init) => {
      providerBodies.push(JSON.parse(init.body));
      return Response.json(namedEnvelope);
    },
  });

  const response = await handler(request(namedPayload));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.policyVersion, 'daily-v2');
  assert.deepEqual(
    Object.keys(body).sort(),
    ['caution', 'day', 'generatedAt', 'menus', 'model', 'policyVersion', 'reviewId', 'source', 'summary', 'tip'].sort(),
  );
  assert.deepEqual(body.menus.map((entry) => entry.itemId), ['m0', 'm1']);
  assert.equal(body.menus[0].taste, '고소하고 쫀득한 밥이야.');
  const forwarded = JSON.stringify(providerBodies[0]);
  assert.equal(forwarded.includes('현미밥'), true);
  assert.equal(forwarded.includes('닭갈비'), true);
  assert.equal(providerBodies[0].max_tokens, 4608);
});

test('mixed named and anonymous items are rejected before provider use', async () => {
  const createMealCoachHandler = await loadHandler();
  let providerCalls = 0;
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async () => { providerCalls += 1; return Response.json(namedEnvelope); },
  });

  const mixed = {
    ...namedPayload,
    items: [
      { id: 'm0', name: '현미밥', nutrients: ['carbohydrate'] },
      { id: 'm1', nutrients: ['protein'] },
    ],
  };
  const response = await handler(request(mixed));
  assert.equal(response.status, 400);
  assert.equal(providerCalls, 0);
});

test('unsafe or shapeless menu names are rejected before provider use', async () => {
  const createMealCoachHandler = await loadHandler();
  let providerCalls = 0;
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async () => { providerCalls += 1; return Response.json(namedEnvelope); },
  });

  for (const name of ['<script>', 'https://bad.example', '', '   ', '메뉴'.repeat(20), '이름\n주입']) {
    const bad = { ...namedPayload, items: [{ id: 'm0', name, nutrients: ['carbohydrate'] }, namedPayload.items[1]] };
    assert.equal((await handler(request(bad))).status, 400, JSON.stringify(name));
  }
  assert.equal(providerCalls, 0);
});

test('v2 answers missing a menu or naming unknown nutrients fail as unavailable', async () => {
  const createMealCoachHandler = await loadHandler();
  const finishes = [];
  const missing = structuredClone(namedEnvelope);
  missing.choices[0].message.content = JSON.stringify({
    summary: '오늘 식단을 살펴봤어.',
    menus: [{ itemId: 'm0', nutrient: 'carbohydrate', taste: '고소해.', role: '에너지원이야.', point: '잘 씹어 먹어.' }],
    caution: '실제로 먹은 양은 알 수 없어.',
    tip: '다음 식사에서 만나 보자.',
  });
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async (value) => { finishes.push(value); },
    fetcher: async () => Response.json(missing),
  });

  const response = await handler(request(namedPayload));
  assert.equal(response.status, 502);
  assert.equal(finishes[0].success, false);

  const wrongNutrient = structuredClone(namedEnvelope);
  wrongNutrient.choices[0].message.content = JSON.stringify({
    summary: '오늘 식단을 살펴봤어.',
    menus: [
      { itemId: 'm0', nutrient: 'calcium', taste: '고소해.', role: '뼈를 이루는 데 쓰여.', point: '잘 씹어 먹어.' },
      { itemId: 'm1', nutrient: 'protein', taste: '쫄깃해.', role: '몸을 만드는 재료야.', point: '채소와 함께 먹어.' },
    ],
    caution: '실제로 먹은 양은 알 수 없어.',
    tip: '다음 식사에서 만나 보자.',
  });
  const second = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async () => Response.json(wrongNutrient),
  });
  assert.equal((await second(request(namedPayload))).status, 502);
});

test('remote provider config can disable AI before quota or provider use', async () => {
  const createMealCoachHandler = await loadHandler();
  let claims = 0;
  let providerCalls = 0;
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    resolveProvider: async () => ({ enabled: false, key: '', url: '', model: '' }),
    claim: async () => { claims += 1; return 'claimed'; },
    finish: async () => {},
    fetcher: async () => { providerCalls += 1; return Response.json(providerEnvelope); },
  });

  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'ai_disabled');
  assert.equal(claims, 0, 'disabled remote config must not consume the daily claim');
  assert.equal(providerCalls, 0);
});

test('remote provider config supplies the key, model and endpoint per request', async () => {
  const createMealCoachHandler = await loadHandler();
  const seen = [];
  const handler = createMealCoachHandler({
    providerKey: 'env-key-must-not-be-used',
    resolveProvider: async () => ({
      enabled: true,
      key: 'rotated-nas-key',
      url: 'https://provider.example/v2/chat',
      model: 'rotated-model',
    }),
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async (url, init) => {
      seen.push({ url: String(url), auth: init.headers.Authorization, body: JSON.parse(init.body) });
      return Response.json(providerEnvelope);
    },
  });

  const response = await handler(request());
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.model, 'rotated-model');
  assert.equal(seen[0].url, 'https://provider.example/v2/chat');
  assert.equal(seen[0].auth, 'Bearer rotated-nas-key');
  assert.equal(seen[0].body.model, 'rotated-model');
});

test('a failing provider resolver falls back to the static env key', async () => {
  const createMealCoachHandler = await loadHandler();
  const seen = [];
  const handler = createMealCoachHandler({
    providerKey: 'env-still-works',
    resolveProvider: async () => { throw new Error('resolver blew up'); },
    claim: async () => 'claimed',
    finish: async () => {},
    fetcher: async (url, init) => {
      seen.push(init.headers.Authorization);
      return Response.json(providerEnvelope);
    },
  });

  assert.equal((await handler(request())).status, 200);
  assert.equal(seen[0], 'Bearer env-still-works');
});
