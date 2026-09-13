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
  const handler = createMealCoachHandler({
    providerKey: 'provider-secret-for-test-only',
    now: () => new Date('2026-09-13T03:00:00.000Z'),
    claim: async (value) => { claims.push(value); return 'claimed'; },
    finish: async (value) => { finishes.push(value); },
    fetcher: async (_url, init) => {
      providerBodies.push(JSON.parse(init.body));
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
  assert.equal(forwarded.includes('현미밥'), false);
  assert.equal(forwarded.includes('학교'), false);
  assert.equal(forwarded.includes(payload.sessionId), false);
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
