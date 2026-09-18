import type { MealItem } from '../domain/types';
import { hasAllergyRisk } from '../domain/allergy';

export const NUTRIENT_ORDER = ['fiber', 'vitamin', 'protein', 'iron', 'calcium', 'carbohydrate'] as const;
export type NutrientId = (typeof NUTRIENT_ORDER)[number];

export const NUTRIENT_LABELS: Record<NutrientId, string> = {
  fiber: '식이섬유',
  vitamin: '비타민',
  protein: '단백질',
  iron: '철분',
  calcium: '칼슘',
  carbohydrate: '탄수화물',
};

const NUTRIENT_ID_BY_LABEL: Record<string, NutrientId> = {
  식이섬유: 'fiber',
  비타민: 'vitamin',
  단백질: 'protein',
  철분: 'iron',
  칼슘: 'calcium',
  탄수화물: 'carbohydrate',
};

const NUTRIENT_IDS = new Set<string>(NUTRIENT_ORDER);

export function normalizeNutrients(raw: string[]): NutrientId[] {
  const found = new Set<NutrientId>();
  for (const entry of raw) {
    const id = NUTRIENT_IDS.has(entry) ? entry as NutrientId : NUTRIENT_ID_BY_LABEL[entry.trim()];
    if (id) found.add(id);
  }
  return NUTRIENT_ORDER.filter((id) => found.has(id));
}

const INVALID_MENU_NAME = /[<>{}[\]\p{C}]|https?:/iu;

export function validMenuName(name: string) {
  const trimmed = name.trim();
  return trimmed.length >= 1 && trimmed.length <= 30 && /\p{L}/u.test(trimmed) && !INVALID_MENU_NAME.test(trimmed);
}

export interface MealReviewItem {
  id: string;
  name: string;
  nutrients: NutrientId[];
}

export function buildReviewItems(menuItems: MealItem[], allergyCodes: number[]): MealReviewItem[] {
  return menuItems
    .filter((item) => !hasAllergyRisk(item.allergyCodes, allergyCodes))
    .map((item) => {
      const nutrients = normalizeNutrients(item.nutrients);
      // 분류되지 않은 메뉴도 리뷰 대상이다. 영양소를 추정할 수 없으면
      // 전체 영양소 집합을 보내 코치가 메뉴 이름만으로 설명하게 한다.
      return { name: item.name.trim(), nutrients: nutrients.length > 0 ? nutrients : [...NUTRIENT_ORDER] };
    })
    .filter((item) => validMenuName(item.name))
    .slice(0, 15)
    .map((item, index) => ({ id: `m${index}`, name: item.name, nutrients: item.nutrients }));
}

export interface MealReviewMenu {
  itemId: string;
  nutrient: NutrientId;
  taste: string;
  role: string;
  point: string;
}

export interface MealReviewResult {
  source: 'ai';
  reviewId: string;
  day: string;
  generatedAt: string;
  model: string;
  policyVersion: 'daily-v2';
  summary: string;
  menus: MealReviewMenu[];
  caution: string;
  tip: string;
}

export type MealCoachErrorKind =
  | 'NETWORK'
  | 'TIMEOUT'
  | 'TOO_LARGE'
  | 'INVALID_REQUEST'
  | 'CONFLICT'
  | 'DAILY_LIMIT'
  | 'GLOBAL_LIMIT'
  | 'UNAVAILABLE'
  | 'INVALID_RESPONSE';

export class MealCoachError extends Error {
  constructor(public readonly kind: MealCoachErrorKind, message: string) { super(message); }
}

export function mealCoachErrorMessage(error: unknown) {
  const kind = error instanceof MealCoachError ? error.kind : 'NETWORK';
  if (kind === 'DAILY_LIMIT') return '오늘의 AI 해설은 이미 확인했어요. 내일 다시 만나요.';
  if (kind === 'GLOBAL_LIMIT') return '지금은 AI 해설 요청이 많아요. 잠시 후 다시 시도해 주세요.';
  if (kind === 'NETWORK' || kind === 'TIMEOUT') return '네트워크 연결을 확인하고 다시 시도해 주세요.';
  return 'AI 해설을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
}

const MAX_REQUEST_BYTES = 8 * 1024;
const MAX_RESPONSE_BYTES = 16 * 1024;
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_TEXT_LENGTH = 240;

function byteLength(text: string) {
  return new TextEncoder().encode(text).length;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isSafeText(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= MAX_TEXT_LENGTH;
}

function validateResponse(value: unknown, requestId: string, items: MealReviewItem[]): MealReviewResult {
  if (!isObject(value) || value.source !== 'ai' || value.policyVersion !== 'daily-v2') {
    throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
  }
  if (typeof value.reviewId !== 'string' || value.reviewId.toLowerCase() !== requestId.toLowerCase()) {
    throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
  }
  const { day, generatedAt, model, summary, caution, tip } = value;
  if (typeof day !== 'string' || !day || typeof generatedAt !== 'string' || !generatedAt || typeof model !== 'string' || !model) {
    throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
  }
  if (!isSafeText(summary) || !isSafeText(caution) || !isSafeText(tip)) {
    throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
  }
  if (!Array.isArray(value.menus) || value.menus.length !== items.length) {
    throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
  }
  const allowed = new Map(items.map((item) => [item.id, new Set<string>(item.nutrients)]));
  const seen = new Set<string>();
  const menus = value.menus.map((entry): MealReviewMenu => {
    if (!isObject(entry) || typeof entry.itemId !== 'string' || typeof entry.nutrient !== 'string') {
      throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
    }
    const nutrients = allowed.get(entry.itemId);
    if (!nutrients || !nutrients.has(entry.nutrient) || seen.has(entry.itemId)) {
      throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
    }
    seen.add(entry.itemId);
    if (!isSafeText(entry.taste) || !isSafeText(entry.role) || !isSafeText(entry.point)) {
      throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답 형식이 올바르지 않아요.');
    }
    return { itemId: entry.itemId, nutrient: entry.nutrient as NutrientId, taste: entry.taste, role: entry.role, point: entry.point };
  });
  return {
    source: 'ai',
    reviewId: value.reviewId,
    day,
    generatedAt,
    model,
    policyVersion: 'daily-v2',
    summary,
    menus,
    caution,
    tip,
  };
}

export interface MealCoachClientConfig {
  url: string;
}

export function createMealCoachClient(config: MealCoachClientConfig) {
  return {
    async review(request: { requestId: string; sessionId: string; items: MealReviewItem[] }): Promise<MealReviewResult> {
      const body = JSON.stringify({ requestId: request.requestId, sessionId: request.sessionId, items: request.items, wholeMeal: {} });
      if (byteLength(body) > MAX_REQUEST_BYTES) throw new MealCoachError('TOO_LARGE', 'AI 해설 요청이 너무 커요.');
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      let response: Response;
      try {
        response = await fetch(config.url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body,
          signal: controller.signal,
        });
      } catch (error) {
        const aborted = error instanceof Error && (error.name === 'AbortError' || error.name === 'TimeoutError');
        throw new MealCoachError(aborted ? 'TIMEOUT' : 'NETWORK', 'AI 해설 서버에 연결하지 못했어요.');
      } finally {
        clearTimeout(timer);
      }
      let text: string;
      try {
        text = await response.text();
      } catch {
        throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답을 읽지 못했어요.');
      }
      if (byteLength(text) > MAX_RESPONSE_BYTES) throw new MealCoachError('TOO_LARGE', 'AI 해설 응답이 너무 커요.');
      let parsed: unknown;
      try {
        parsed = JSON.parse(text) as unknown;
      } catch {
        throw new MealCoachError('INVALID_RESPONSE', 'AI 해설 응답을 읽지 못했어요.');
      }
      if (!response.ok) {
        const code = isObject(parsed) && typeof parsed.error === 'string' ? parsed.error : '';
        if (response.status === 429) throw new MealCoachError(code === 'global_limit' ? 'GLOBAL_LIMIT' : 'DAILY_LIMIT', 'AI 해설 요청 한도에 도달했어요.');
        if (response.status === 400) throw new MealCoachError('INVALID_REQUEST', 'AI 해설 요청이 올바르지 않아요.');
        if (response.status === 409) throw new MealCoachError('CONFLICT', 'AI 해설 요청이 이미 처리 중이에요.');
        throw new MealCoachError('UNAVAILABLE', 'AI 해설 서버를 점검하고 있어요.');
      }
      return validateResponse(parsed, request.requestId, request.items);
    },
  };
}
