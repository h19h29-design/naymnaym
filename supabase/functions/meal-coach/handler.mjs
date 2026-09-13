const GO_MODEL = 'deepseek-v4.1-flash';
const GO_URL = 'https://opencode.ai/zen/go/v1/chat/completions';
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const ITEM_ID = /^m(?:[0-9]|[12][0-9])$/;
const NUTRIENTS = new Set(['fiber', 'vitamin', 'protein', 'iron', 'calcium', 'carbohydrate']);
const RESPONSE_KEYS = ['summary', 'benefit', 'highlights', 'caution', 'tip'];
const TEXT_KEYS = ['summary', 'benefit', 'caution', 'tip'];

const INSTRUCTION = `너는 급식레벨업의 AI 영양 안내 캐릭터야. 실제 영양사나 의료인이 아니야.
익명 메뉴 items의 nutrients는 메뉴 기반 추정이지 함량 증명이 아니야. wholeMeal은 제공된 식사 전체 영양량이며 개인 섭취량이나 반찬별 함량이 아니야.
오늘 식단의 대표 영양소 역할, 눈여겨볼 후보, 다른 식사에서 부담 없이 보완하는 방법을 한국어 반말로 설명해.
각 항목은 가급적 한 문장, 짧게 작성해. 숫자나 측정단위, 수량 표현을 출력하지 마. wholeMeal이 비면 없는 수치나 함량을 가리키지 마.
주어진 영양소 외의 성분을 있다고 단정하지 마. 결핍·과잉·체중·성장·질환 효과를 판단하거나 먹도록 강요하지 마. 조리·신선도·안전을 보장하거나 알레르기 극복, 질병, 혈압, 혈당, 빈혈을 설명하지 마.
메뉴 이름은 모르므로 만들지 마. highlights는 요청 items 중 최대 두 개만 선택하고 그 항목에 있는 nutrient ID 하나와 일반적인 역할만 써.
JSON만 반환해: summary, benefit, highlights, caution, tip. 각 문자열 최대 240자, 가급적 60자 이내.`;

class HandlerFailure extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}

function response(body, status = 200) {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
    },
  });
}

function exactObject(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new HandlerFailure('invalid');
  const actual = Object.keys(value);
  if (actual.length !== keys.length || actual.some((key) => !keys.includes(key))) throw new HandlerFailure('invalid');
}

function validateRequest(value) {
  exactObject(value, ['requestId', 'sessionId', 'items', 'wholeMeal']);
  if (!UUID.test(value.requestId) || !UUID.test(value.sessionId) || !Array.isArray(value.items) || value.items.length < 1 || value.items.length > 30) {
    throw new HandlerFailure('invalid');
  }
  exactObject(value.wholeMeal, Object.keys(value.wholeMeal));
  if (Object.keys(value.wholeMeal).some((key) => !['protein', 'carbs', 'fat'].includes(key))) throw new HandlerFailure('invalid');
  if (Object.values(value.wholeMeal).some((amount) => typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0 || amount > 1000)) {
    throw new HandlerFailure('invalid');
  }
  const seen = new Set();
  const items = value.items.map((item) => {
    exactObject(item, ['id', 'nutrients']);
    if (!ITEM_ID.test(item.id) || seen.has(item.id) || !Array.isArray(item.nutrients) || item.nutrients.length < 1 || item.nutrients.length > 6) {
      throw new HandlerFailure('invalid');
    }
    if (new Set(item.nutrients).size !== item.nutrients.length || item.nutrients.some((nutrient) => !NUTRIENTS.has(nutrient))) {
      throw new HandlerFailure('invalid');
    }
    seen.add(item.id);
    return { id: item.id, nutrients: [...item.nutrients] };
  });
  return {
    requestId: value.requestId.toLowerCase(),
    sessionId: value.sessionId.toLowerCase(),
    items,
    wholeMeal: Object.fromEntries(Object.keys(value.wholeMeal).sort().map((key) => [key, value.wholeMeal[key]])),
  };
}

function validateText(value, input) {
  if (typeof value !== 'string' || !value.trim() || value.length > 240 || !/[가-힣]/u.test(value)) throw new HandlerFailure('answer_format');
  const forbidden = /\p{N}|그램|칼로리|\b(?:mg|g|kcal)\b|안전|익혀|조리|신선|혈압|혈당|빈혈|https?:|www\.|<|>|키가\s*안\s*커|먹어도\s*괜찮|알레르기.{0,12}(?:무시|극복)|치료|완치|질병|비만|다이어트|살이\s*찌|키가\s*커|결핍입니다|부족합니다|반드시\s*먹|꼭\s*먹|ignore|instructions|system\s*prompt/iu;
  if (forbidden.test(value)) throw new HandlerFailure('answer_safety');
  if (Object.keys(input.wholeMeal).length === 0 && /(?:이|그|해당|위|주어진|제공된)\s*(?:수치|함량|숫자|수량)/u.test(value)) {
    throw new HandlerFailure('answer_grounding');
  }
  return value.trim();
}

function validateAnswer(value, input) {
  exactObject(value, RESPONSE_KEYS);
  if (!Array.isArray(value.highlights) || value.highlights.length > 2) throw new HandlerFailure('answer_format');
  const answer = Object.fromEntries(TEXT_KEYS.map((key) => [key, validateText(value[key], input)]));
  const seen = new Set();
  const highlights = value.highlights.map((highlight) => {
    exactObject(highlight, ['itemId', 'nutrient', 'reason']);
    const item = input.items.find((candidate) => candidate.id === highlight.itemId);
    if (!item || !item.nutrients.includes(highlight.nutrient) || seen.has(highlight.itemId)) throw new HandlerFailure('answer_grounding');
    seen.add(highlight.itemId);
    return { itemId: highlight.itemId, nutrient: highlight.nutrient, reason: validateText(highlight.reason, input) };
  });
  return { ...answer, highlights };
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function koreaDay(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(date);
}

async function readTextWithin(responseBody, maximumBytes) {
  const text = await responseBody.text();
  if (new TextEncoder().encode(text).byteLength > maximumBytes) throw new HandlerFailure('answer_too_large');
  return text;
}

export function createMealCoachHandler({ providerKey, claim, finish, fetcher = fetch, now = () => new Date() }) {
  if (typeof providerKey !== 'string' || typeof claim !== 'function' || typeof finish !== 'function') throw new Error('invalid_configuration');
  return async (request) => {
    if (request.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);
    if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) return response({ error: 'invalid_content_type' }, 415);
    let input;
    try {
      const text = await request.text();
      if (new TextEncoder().encode(text).byteLength > 8192) return response({ error: 'request_too_large' }, 413);
      input = validateRequest(JSON.parse(text));
    } catch {
      return response({ error: 'invalid_request' }, 400);
    }
    if (!providerKey.trim()) return response({ error: 'not_configured' }, 503);
    const instant = now();
    const day = koreaDay(instant);
    const subjectHash = await sha256(input.sessionId);
    const requestHash = await sha256(input.requestId);
    const fingerprint = await sha256(JSON.stringify({ items: input.items, wholeMeal: input.wholeMeal }));
    let claimResult;
    try { claimResult = await claim({ subjectHash, day, requestHash, fingerprint }); }
    catch { return response({ error: 'storage_unavailable' }, 503); }
    if (claimResult !== 'claimed') {
      const status = ['daily_attempt_limit', 'global_limit'].includes(claimResult) ? 429 : claimResult === 'storage_unavailable' ? 503 : 409;
      return response({ error: claimResult }, status);
    }

    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 15000);
    try {
      const providerResponse = await fetcher(GO_URL, {
        method: 'POST',
        redirect: 'error',
        signal: abort.signal,
        headers: {
          Authorization: `Bearer ${providerKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'geupsik-levelup-meal-coach/1.0',
        },
        body: JSON.stringify({
          model: GO_MODEL,
          max_tokens: 1100,
          temperature: 0.3,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: INSTRUCTION },
            { role: 'user', content: JSON.stringify({ items: input.items, wholeMeal: input.wholeMeal }) },
          ],
        }),
      });
      if (!providerResponse.ok) throw new HandlerFailure('provider_unavailable');
      const envelope = JSON.parse(await readTextWithin(providerResponse, 16384));
      if (envelope?.choices?.[0]?.finish_reason === 'length') throw new HandlerFailure('answer_truncated');
      const value = JSON.parse(envelope?.choices?.[0]?.message?.content ?? '');
      const answer = validateAnswer(value, input);
      await finish({ subjectHash, day, requestHash, success: true });
      return response({
        source: 'ai', reviewId: input.requestId, day, generatedAt: now().toISOString(),
        model: GO_MODEL, policyVersion: 'daily-v1', ...answer,
      });
    } catch {
      try { await finish({ subjectHash, day, requestHash, success: false }); } catch { return response({ error: 'storage_unavailable' }, 503); }
      return response({ error: 'answer_unavailable' }, 502);
    } finally {
      clearTimeout(timeout);
    }
  };
}
