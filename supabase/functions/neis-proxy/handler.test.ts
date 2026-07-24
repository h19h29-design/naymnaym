import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { createHandler } from './handler.ts';

const ALLOWED_ORIGIN = 'https://sandbox.example';
const API_KEY = 'server-secret';

function request(
  body: unknown,
  options: {
    method?: string;
    origin?: string;
    headers?: HeadersInit;
  } = {},
): Request {
  return new Request('https://edge.test', {
    method: options.method ?? 'POST',
    headers: {
      origin: options.origin ?? ALLOWED_ORIGIN,
      ...options.headers,
    },
    body: options.method && options.method !== 'POST'
      ? undefined
      : JSON.stringify(body),
  });
}

function deps(
  fetchImpl: typeof fetch = async () =>
    new Response(JSON.stringify({
      schoolInfo: [
        {
          head: [
            { list_total_count: 0 },
            { RESULT: { CODE: 'INFO-000', MESSAGE: '정상 처리되었습니다.' } },
          ],
        },
        { row: [] },
      ],
    })),
  log: (message: string) => void = () => {},
) {
  return {
    allowedOrigins: new Set([ALLOWED_ORIGIN]),
    neisApiKey: API_KEY,
    fetch: fetchImpl,
    log,
  };
}

async function body(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

Deno.test('rejects an unlisted browser origin without CORS permission', async () => {
  const response = await createHandler(deps())(
    request(
      { action: 'searchSchools', payload: { keyword: '가람' } },
      { origin: 'https://evil.example' },
    ),
  );

  assertEquals(response.status, 403);
  assertEquals(response.headers.get('access-control-allow-origin'), null);
  assertEquals(await body(response), {
    ok: false,
    code: 'FORBIDDEN_ORIGIN',
    message: '허용되지 않은 요청이에요.',
  });
});

Deno.test('permits preflight only for an exact allowed origin', async () => {
  const handler = createHandler(deps());
  const allowed = await handler(request({}, { method: 'OPTIONS' }));
  const suffix = await handler(
    request({}, {
      method: 'OPTIONS',
      origin: `${ALLOWED_ORIGIN}.evil.example`,
    }),
  );

  assertEquals(allowed.status, 204);
  assertEquals(
    allowed.headers.get('access-control-allow-origin'),
    ALLOWED_ORIGIN,
  );
  assertEquals(
    allowed.headers.get('access-control-allow-methods'),
    'POST, OPTIONS',
  );
  assertEquals(
    allowed.headers.get('access-control-allow-headers'),
    'authorization, apikey, content-type',
  );
  assertEquals(allowed.headers.get('access-control-max-age'), '600');
  assertEquals(allowed.headers.get('vary'), 'Origin');
  assertEquals(suffix.status, 403);
});

Deno.test('rejects every non-POST application method before upstream fetch', async () => {
  let calls = 0;
  const handler = createHandler(deps(async () => {
    calls++;
    return new Response();
  }));

  for (const method of ['GET', 'PUT', 'PATCH', 'DELETE']) {
    const response = await handler(request({}, { method }));
    assertEquals(response.status, 405);
    assertEquals((await body(response)).code, 'BAD_REQUEST');
  }
  assertEquals(calls, 0);
});

Deno.test('rejects an advertised body over 4096 bytes without reading upstream', async () => {
  let calls = 0;
  const response = await createHandler(deps(async () => {
    calls++;
    return new Response();
  }))(request(
    { action: 'searchSchools', payload: { keyword: '가람' } },
    { headers: { 'content-length': '4097' } },
  ));

  assertEquals(response.status, 413);
  assertEquals(calls, 0);
  assertEquals((await body(response)).code, 'BAD_REQUEST');
});

Deno.test('rejects an actual UTF-8 body over 4096 bytes without upstream fetch', async () => {
  let calls = 0;
  const raw = JSON.stringify({
    action: 'searchSchools',
    payload: { keyword: '가'.repeat(1400) },
  });
  assert(new TextEncoder().encode(raw).byteLength > 4096);
  const response = await createHandler(deps(async () => {
    calls++;
    return new Response();
  }))(
    new Request('https://edge.test', {
      method: 'POST',
      headers: { origin: ALLOWED_ORIGIN },
      body: raw,
    }),
  );

  assertEquals(response.status, 413);
  assertEquals(calls, 0);
});

Deno.test('rejects invalid JSON without echoing it', async () => {
  const sentinel = 'private-user-payload';
  const response = await createHandler(deps())(
    new Request('https://edge.test', {
      method: 'POST',
      headers: { origin: ALLOWED_ORIGIN },
      body: `{"${sentinel}"`,
    }),
  );
  const text = await response.text();

  assertEquals(response.status, 400);
  assertEquals(text.includes(sentinel), false);
  assertStringIncludes(text, 'BAD_REQUEST');
});

Deno.test('accepts only the exact action and payload fields', async () => {
  let calls = 0;
  const handler = createHandler(deps(async () => {
    calls++;
    return new Response();
  }));
  const invalidBodies = [
    { action: 'unknown', payload: {} },
    { action: 'searchSchools', payload: { keyword: '가람', extra: true } },
    { action: 'searchSchools', payload: { keyword: '가람' }, extra: true },
    { action: 'searchSchools', payload: ['가람'] },
    null,
  ];

  for (const invalidBody of invalidBodies) {
    const response = await handler(request(invalidBody));
    assertEquals(response.status, 400);
    assertEquals((await body(response)).code, 'BAD_REQUEST');
  }
  assertEquals(calls, 0);
});

Deno.test('trims a valid keyword and rejects unsafe or out-of-range keywords', async () => {
  const requested: URL[] = [];
  const handler = createHandler(deps(async (input) => {
    requested.push(new URL(String(input)));
    return new Response(JSON.stringify({
      schoolInfo: [
        {
          head: [
            { list_total_count: 0 },
            { RESULT: { CODE: 'INFO-000' } },
          ],
        },
        { row: [] },
      ],
    }));
  }));

  const valid = await handler(
    request({ action: 'searchSchools', payload: { keyword: '  가람중  ' } }),
  );
  assertEquals(valid.status, 200);
  assertEquals(requested[0].searchParams.get('SCHUL_NM'), '가람중');

  for (
    const keyword of [
      ' ',
      '가',
      '<script>',
      '가'.repeat(41),
      123,
    ]
  ) {
    const response = await handler(
      request({ action: 'searchSchools', payload: { keyword } }),
    );
    assertEquals(response.status, 400);
  }
  assertEquals(requested.length, 1);
});

Deno.test('rejects malformed meal identifiers and impossible dates before fetch', async () => {
  let calls = 0;
  const handler = createHandler(deps(async () => {
    calls++;
    return new Response();
  }));
  const invalidPayloads = [
    { officeCode: 'bad', schoolCode: '7011234', date: '20260724' },
    { officeCode: 'B10', schoolCode: '1', date: '20260724' },
    { officeCode: 'B10', schoolCode: '7011234', date: '20261390' },
    { officeCode: 'B10', schoolCode: '7011234', date: '20260229' },
    {
      officeCode: 'B10',
      schoolCode: '7011234',
      date: '20260724',
      extra: true,
    },
  ];

  for (const payload of invalidPayloads) {
    const response = await handler(
      request({ action: 'fetchMeals', payload }),
    );
    assertEquals(response.status, 400);
  }
  assertEquals(calls, 0);
});

Deno.test('allows a real leap-day meal date', async () => {
  let calls = 0;
  const response = await createHandler(deps(async () => {
    calls++;
    return new Response(JSON.stringify({
      RESULT: { CODE: 'INFO-200', MESSAGE: '해당하는 데이터가 없습니다.' },
    }));
  }))(request({
    action: 'fetchMeals',
    payload: {
      officeCode: 'B10',
      schoolCode: '7011234',
      date: '20240229',
    },
  }));

  assertEquals(response.status, 404);
  assertEquals(calls, 1);
});

Deno.test('returns NOT_CONFIGURED when the key or origin allowlist is empty', async () => {
  const configured = deps();
  for (
    const missing of [
      { ...configured, neisApiKey: '' },
      { ...configured, allowedOrigins: new Set<string>() },
    ]
  ) {
    const response = await createHandler(missing)(
      request({ action: 'searchSchools', payload: { keyword: '가람' } }),
    );
    assertEquals(response.status, 503);
    assertEquals(await body(response), {
      ok: false,
      code: 'NOT_CONFIGURED',
      message: '급식 조회가 준비되지 않았어요.',
    });
    assertEquals(response.headers.get('access-control-allow-origin'), null);
  }
});

Deno.test('calls only the fixed schoolInfo endpoint and normalizes school rows', async () => {
  let upstreamUrl: URL | undefined;
  const response = await createHandler(deps(async (input) => {
    upstreamUrl = new URL(String(input));
    return new Response(JSON.stringify({
      schoolInfo: [
        {
          head: [
            { list_total_count: 2 },
            { RESULT: { CODE: 'INFO-000' } },
          ],
        },
        {
          row: [
            {
              SCHUL_NM: ' 가람중학교 ',
              ATPT_OFCDC_SC_CODE: 'B10',
              SD_SCHUL_CODE: '7011234',
              LCTN_SC_NM: ' 서울특별시 ',
              ORG_RDNMA: ' 서울 중구 1 ',
              SCHUL_KND_SC_NM: '중학교',
            },
            {
              SCHUL_NM: '가람초등학교',
              ATPT_OFCDC_SC_CODE: 'B10',
              SD_SCHUL_CODE: '7015678',
              LCTN_SC_NM: '서울특별시',
              ORG_RDNMA: '서울 중구 2',
              SCHUL_KND_SC_NM: '초등학교',
            },
          ],
        },
      ],
    }));
  }))(request({
    action: 'searchSchools',
    payload: { keyword: '가람' },
  }));

  assertEquals(response.status, 200);
  assertEquals(upstreamUrl?.origin, 'https://open.neis.go.kr');
  assertEquals(upstreamUrl?.pathname, '/hub/schoolInfo');
  assertEquals(upstreamUrl?.searchParams.get('KEY'), API_KEY);
  assertEquals(upstreamUrl?.searchParams.get('Type'), 'json');
  assertEquals(upstreamUrl?.searchParams.get('pIndex'), '1');
  assertEquals(upstreamUrl?.searchParams.get('pSize'), '20');
  assertEquals(upstreamUrl?.searchParams.get('SCHUL_NM'), '가람');
  assertEquals(await body(response), {
    ok: true,
    data: [{
      name: '가람중학교',
      officeCode: 'B10',
      schoolCode: '7011234',
      region: '서울특별시',
      address: '서울 중구 1',
      schoolType: 'middle',
    }],
  });
});

Deno.test('calls only the fixed meal endpoint and returns a normalized meal', async () => {
  let upstreamUrl: URL | undefined;
  const response = await createHandler(deps(async (input) => {
    upstreamUrl = new URL(String(input));
    return new Response(JSON.stringify({
      mealServiceDietInfo: [
        {
          head: [
            { list_total_count: 1 },
            { RESULT: { CODE: 'INFO-000' } },
          ],
        },
        {
          row: [{
            MLSV_YMD: '20260724',
            DDISH_NM: '현미밥<br/>닭갈비(5.6.15.)',
            CAL_INFO: '812.3 Kcal',
            NTR_INFO: '단백질(g) : 32.0',
          }],
        },
      ],
    }));
  }))(request({
    action: 'fetchMeals',
    payload: {
      officeCode: 'B10',
      schoolCode: '7011234',
      date: '20260724',
    },
  }));

  assertEquals(response.status, 200);
  assertEquals(upstreamUrl?.origin, 'https://open.neis.go.kr');
  assertEquals(upstreamUrl?.pathname, '/hub/mealServiceDietInfo');
  assertEquals(upstreamUrl?.searchParams.get('pSize'), '10');
  assertEquals(upstreamUrl?.searchParams.get('MMEAL_SC_CODE'), '2');
  assertEquals(
    upstreamUrl?.searchParams.get('ATPT_OFCDC_SC_CODE'),
    'B10',
  );
  assertEquals(upstreamUrl?.searchParams.get('SD_SCHUL_CODE'), '7011234');
  assertEquals(upstreamUrl?.searchParams.get('MLSV_YMD'), '20260724');
  const result = await body(response);
  assertEquals(result.ok, true);
  assertEquals((result.data as { date: string }).date, '20260724');
});

Deno.test('maps explicit top-level and resource-head no-data envelopes safely', async () => {
  const noDataEnvelopes = [
    { RESULT: { CODE: 'INFO-200', MESSAGE: '해당하는 데이터가 없습니다.' } },
    {
      mealServiceDietInfo: [{
        head: [
          { list_total_count: 0 },
          { RESULT: { CODE: 'INFO-200' } },
        ],
      }],
    },
  ];

  for (const envelope of noDataEnvelopes) {
    const response = await createHandler(
      deps(async () => new Response(JSON.stringify(envelope))),
    )(request({
      action: 'fetchMeals',
      payload: {
        officeCode: 'B10',
        schoolCode: '7011234',
        date: '20260724',
      },
    }));
    assertEquals(response.status, 404);
    assertEquals((await body(response)).code, 'NO_DATA');
  }
});

Deno.test('returns an empty list for an explicit no-data school response', async () => {
  const response = await createHandler(
    deps(async () =>
      new Response(JSON.stringify({
        RESULT: { CODE: 'INFO-200' },
      }))
    ),
  )(request({
    action: 'searchSchools',
    payload: { keyword: '가람' },
  }));

  assertEquals(response.status, 200);
  assertEquals(await body(response), { ok: true, data: [] });
});

Deno.test('does not mistake a NEIS error envelope with no rows for no data', async () => {
  const response = await createHandler(
    deps(async () =>
      new Response(JSON.stringify({
        mealServiceDietInfo: [{
          head: [
            { list_total_count: 0 },
            { RESULT: { CODE: 'ERROR-300', MESSAGE: 'invalid key detail' } },
          ],
        }],
      }))
    ),
  )(request({
    action: 'fetchMeals',
    payload: {
      officeCode: 'B10',
      schoolCode: '7011234',
      date: '20260724',
    },
  }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertStringIncludes(text, 'UPSTREAM_ERROR');
  assertEquals(text.includes('invalid key detail'), false);
});

Deno.test('treats malformed or wrong-resource success bodies as upstream errors', async () => {
  for (
    const envelope of [
      {},
      { schoolInfo: 'not-an-array' },
      {
        schoolInfo: [{
          head: [
            { list_total_count: 1 },
            { RESULT: { CODE: 'INFO-000' } },
          ],
        }],
      },
      {
        mealServiceDietInfo: [
          {
            head: [
              { list_total_count: 1 },
              { RESULT: { CODE: 'INFO-000' } },
            ],
          },
          { row: [] },
        ],
      },
    ]
  ) {
    const response = await createHandler(
      deps(async () => new Response(JSON.stringify(envelope))),
    )(request({
      action: 'searchSchools',
      payload: { keyword: '가람' },
    }));
    assertEquals(response.status, 502);
    assertEquals((await body(response)).code, 'UPSTREAM_ERROR');
  }
});

Deno.test('maps upstream 429 and other HTTP failures without body leakage', async () => {
  const sentinel = 'private-upstream-body';
  const rateLimited = await createHandler(
    deps(async () => new Response(sentinel, { status: 429 })),
  )(request({ action: 'searchSchools', payload: { keyword: '가람' } }));
  const failed = await createHandler(
    deps(async () => new Response(sentinel, { status: 500 })),
  )(request({ action: 'searchSchools', payload: { keyword: '가람' } }));

  assertEquals(rateLimited.status, 429);
  assertEquals((await body(rateLimited)).code, 'RATE_LIMITED');
  const failedText = await failed.text();
  assertEquals(failed.status, 502);
  assertStringIncludes(failedText, 'UPSTREAM_ERROR');
  assertEquals(failedText.includes(sentinel), false);
});

Deno.test('never includes the NEIS key or user payload in an upstream failure', async () => {
  const sentinel = '가람-private-user-payload';
  const response = await createHandler(deps(async () => {
    throw new Error(`upstream failed: ${API_KEY} ${sentinel}`);
  }))(request({
    action: 'searchSchools',
    payload: { keyword: sentinel },
  }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(text.includes(API_KEY), false);
  assertEquals(text.includes(sentinel), false);
  assertStringIncludes(text, 'UPSTREAM_ERROR');
});

Deno.test('logs only request metadata, never secrets, payloads, or URLs', async () => {
  const logs: string[] = [];
  const sentinel = '가람-private-user-payload';
  const response = await createHandler(deps(async () => {
    throw new Error(`failed ${API_KEY} ${sentinel}`);
  }, (message) => logs.push(message)))(request({
    action: 'searchSchools',
    payload: { keyword: sentinel },
  }));

  assertEquals(response.status, 502);
  assertEquals(logs.length, 1);
  const entry = JSON.parse(logs[0]);
  assertEquals(Object.keys(entry).sort(), [
    'action',
    'durationMs',
    'requestId',
    'status',
  ]);
  assertEquals(entry.action, 'searchSchools');
  assertEquals(entry.status, 502);
  assertEquals(logs[0].includes(API_KEY), false);
  assertEquals(logs[0].includes(sentinel), false);
  assertEquals(logs[0].includes('open.neis.go.kr'), false);
});

Deno.test('sets safe response headers and CORS only for the allowed origin', async () => {
  const response = await createHandler(
    deps(async () =>
      new Response(JSON.stringify({
        RESULT: { CODE: 'INFO-200' },
      }))
    ),
  )(request({
    action: 'searchSchools',
    payload: { keyword: '가람' },
  }));

  assertEquals(
    response.headers.get('content-type'),
    'application/json; charset=utf-8',
  );
  assertEquals(response.headers.get('cache-control'), 'no-store');
  assertEquals(
    response.headers.get('access-control-allow-origin'),
    ALLOWED_ORIGIN,
  );
  assertEquals(response.headers.get('vary'), 'Origin');
});
