import type {
  ProxyErrorCode,
  ProxyRequest,
} from "../_shared/neis-contract/index.ts";
import { normalizeMealRows, normalizeSchoolRows } from "./neis-normalizer.ts";
import type { RawMealRow, RawSchoolRow } from "./neis-normalizer.ts";

const MAX_BODY_BYTES = 4096;
const MAX_UPSTREAM_BODY_BYTES = 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 1800;
const OFFICE_CODE = /^[A-Z][0-9]{2}$/;
const SCHOOL_CODE = /^[0-9]{7}$/;
const DATE = /^[0-9]{8}$/;
const SCHOOL_KEYWORD = /^[가-힣A-Za-z0-9\s().-]{2,40}$/;

export interface HandlerDeps {
  allowedOrigins: Set<string>;
  neisApiKey: string;
  clientToken: string;
  fetch: typeof fetch;
  log?: (message: string) => void;
  createTimeoutSignal?: (milliseconds: number) => AbortSignal;
}

function isRealDate(value: string): boolean {
  if (!DATE.test(value)) return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(4, 6));
  const day = Number(value.slice(6, 8));
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const expected = [...keys].sort();
  const actual = Object.keys(value).sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function unwrapRequest(
  value: unknown,
  clientToken: string,
): unknown | undefined {
  if (
    !isObject(value) ||
    !hasOnlyKeys(value, ["clientToken", "request"]) ||
    typeof value.clientToken !== "string" ||
    value.clientToken !== clientToken
  ) {
    return undefined;
  }
  return value.request;
}

async function readLimitedBytes(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array | null> {
  if (stream === null) return new Uint8Array();

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        void reader.cancel().catch(() => {});
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function validateRequest(value: unknown): ProxyRequest | null {
  if (
    !isObject(value) ||
    !hasOnlyKeys(value, ["action", "payload"]) ||
    !isObject(value.payload)
  ) {
    return null;
  }

  if (value.action === "searchSchools") {
    const payloadKeys = Object.keys(value.payload).sort();
    const hasSupportedKeys = (
      payloadKeys.length === 1 &&
      payloadKeys[0] === "keyword"
    ) || (
      payloadKeys.length === 2 &&
      payloadKeys[0] === "keyword" &&
      payloadKeys[1] === "schoolType"
    );
    if (!hasSupportedKeys) return null;
    const keyword = typeof value.payload.keyword === "string"
      ? value.payload.keyword.trim()
      : "";
    const schoolType = value.payload.schoolType;
    if (
      !SCHOOL_KEYWORD.test(keyword) ||
      schoolType !== undefined &&
        schoolType !== "middle" &&
        schoolType !== "high"
    ) {
      return null;
    }
    return {
      action: "searchSchools",
      payload: schoolType === undefined ? { keyword } : { keyword, schoolType },
    };
  }

  if (value.action === "fetchMeals") {
    if (
      !hasOnlyKeys(value.payload, [
        "officeCode",
        "schoolCode",
        "date",
      ])
    ) {
      return null;
    }
    const { officeCode, schoolCode, date } = value.payload;
    return typeof officeCode === "string" &&
        OFFICE_CODE.test(officeCode) &&
        typeof schoolCode === "string" &&
        SCHOOL_CODE.test(schoolCode) &&
        typeof date === "string" &&
        isRealDate(date)
      ? {
        action: "fetchMeals",
        payload: { officeCode, schoolCode, date },
      }
      : null;
  }

  return null;
}

function json(origin: string, status: number, value: unknown): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  if (origin) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
  }
  return new Response(JSON.stringify(value), { status, headers });
}

function error(
  origin: string,
  status: number,
  code: ProxyErrorCode,
  message: string,
): Response {
  return json(origin, status, { ok: false, code, message });
}

function corsHeaders(origin: string): HeadersInit {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type",
    "access-control-max-age": "600",
    "vary": "Origin",
  };
}

function neisUrl(request: ProxyRequest, apiKey: string): URL {
  const resource = request.action === "searchSchools"
    ? "schoolInfo"
    : "mealServiceDietInfo";
  const url = new URL(`https://open.neis.go.kr/hub/${resource}`);
  url.searchParams.set("KEY", apiKey);
  url.searchParams.set("Type", "json");
  url.searchParams.set("pIndex", "1");
  url.searchParams.set(
    "pSize",
    request.action === "searchSchools" ? "20" : "10",
  );

  if (request.action === "searchSchools") {
    url.searchParams.set("SCHUL_NM", request.payload.keyword);
    if (request.payload.schoolType !== undefined) {
      url.searchParams.set(
        "SCHUL_KND_SC_NM",
        request.payload.schoolType === "middle" ? "중학교" : "고등학교",
      );
    }
  } else {
    url.searchParams.set(
      "ATPT_OFCDC_SC_CODE",
      request.payload.officeCode,
    );
    url.searchParams.set("SD_SCHUL_CODE", request.payload.schoolCode);
    url.searchParams.set("MMEAL_SC_CODE", "2");
    url.searchParams.set("MLSV_YMD", request.payload.date);
  }

  return url;
}

function resultCodes(value: unknown, resource: string): string[] {
  if (!isObject(value)) return [];
  const codes: string[] = [];

  if (
    isObject(value.RESULT) &&
    typeof value.RESULT.CODE === "string"
  ) {
    codes.push(value.RESULT.CODE);
  }

  const group = value[resource];
  if (!Array.isArray(group) || !isObject(group[0])) return codes;
  const head = group[0].head;
  if (!Array.isArray(head)) return codes;

  for (const entry of head) {
    if (
      isObject(entry) &&
      isObject(entry.RESULT) &&
      typeof entry.RESULT.CODE === "string"
    ) {
      codes.push(entry.RESULT.CODE);
    }
  }
  return codes;
}

function resourceRows(
  value: unknown,
  resource: string,
): unknown[] | null {
  if (!isObject(value)) return null;
  const group = value[resource];
  if (!Array.isArray(group)) return null;

  for (const entry of group) {
    if (isObject(entry) && Object.hasOwn(entry, "row")) {
      return Array.isArray(entry.row) ? entry.row : null;
    }
  }
  return null;
}

function noData(origin: string, request: ProxyRequest): Response {
  if (request.action === "searchSchools") {
    return json(origin, 200, { ok: true, data: [] });
  }
  return error(
    origin,
    404,
    "NO_DATA",
    "오늘은 등록된 급식이 없어요.",
  );
}

export function createHandler(deps: HandlerDeps) {
  return async (request: Request): Promise<Response> => {
    const started = performance.now();
    const requestId = crypto.randomUUID();
    const origin = request.headers.get("origin") ?? "";
    const log = deps.log ?? ((message: string) => console.info(message));
    let action = "unparsed";
    let status = 500;

    try {
      if (
        !deps.neisApiKey ||
        !deps.clientToken ||
        deps.allowedOrigins.size === 0
      ) {
        status = 503;
        return error(
          "",
          status,
          "NOT_CONFIGURED",
          "급식 조회가 준비되지 않았어요.",
        );
      }

      if (!deps.allowedOrigins.has(origin)) {
        status = 403;
        return error(
          "",
          status,
          "FORBIDDEN_ORIGIN",
          "허용되지 않은 요청이에요.",
        );
      }

      if (request.method === "OPTIONS") {
        status = 204;
        return new Response(null, {
          status,
          headers: corsHeaders(origin),
        });
      }

      if (request.method !== "POST") {
        status = 405;
        const response = error(
          origin,
          status,
          "BAD_REQUEST",
          "POST 요청만 사용할 수 있어요.",
        );
        response.headers.set("allow", "POST, OPTIONS");
        return response;
      }

      const advertised = Number(
        request.headers.get("content-length") ?? "0",
      );
      if (
        Number.isFinite(advertised) &&
        advertised > MAX_BODY_BYTES
      ) {
        status = 413;
        return error(
          origin,
          status,
          "BAD_REQUEST",
          "요청 크기가 너무 커요.",
        );
      }

      const requestBytes = await readLimitedBytes(
        request.body,
        MAX_BODY_BYTES,
      );
      if (requestBytes === null) {
        status = 413;
        return error(
          origin,
          status,
          "BAD_REQUEST",
          "요청 크기가 너무 커요.",
        );
      }

      let decoded: unknown;
      try {
        const raw = new TextDecoder("utf-8", { fatal: true }).decode(
          requestBytes,
        );
        decoded = JSON.parse(raw);
      } catch {
        status = 400;
        return error(
          origin,
          status,
          "BAD_REQUEST",
          "요청 형식이 올바르지 않아요.",
        );
      }

      const unwrapped = unwrapRequest(decoded, deps.clientToken);
      if (unwrapped === undefined) {
        status = 403;
        return error(
          origin,
          status,
          "FORBIDDEN_ORIGIN",
          "허용되지 않은 요청이에요.",
        );
      }

      const parsed = validateRequest(unwrapped);
      if (parsed === null) {
        status = 400;
        return error(
          origin,
          status,
          "BAD_REQUEST",
          "요청 값이 올바르지 않아요.",
        );
      }
      action = parsed.action;

      const timeoutSignal = (deps.createTimeoutSignal ??
        ((milliseconds: number) => AbortSignal.timeout(milliseconds)))(
          UPSTREAM_TIMEOUT_MS,
        );
      const upstream = await deps.fetch(
        neisUrl(parsed, deps.neisApiKey),
        {
          signal: timeoutSignal,
        },
      );
      if (upstream.status === 429) {
        status = 429;
        return error(
          origin,
          status,
          "RATE_LIMITED",
          "요청이 많아요. 잠시 후 다시 시도해 주세요.",
        );
      }
      if (!upstream.ok) {
        status = 502;
        return error(
          origin,
          status,
          "UPSTREAM_ERROR",
          "급식 정보를 불러오지 못했어요.",
        );
      }

      const upstreamBytes = await readLimitedBytes(
        upstream.body,
        MAX_UPSTREAM_BODY_BYTES,
      );
      if (upstreamBytes === null) {
        status = 502;
        return error(
          origin,
          status,
          "UPSTREAM_ERROR",
          "급식 정보를 불러오지 못했어요.",
        );
      }
      const upstreamJson: unknown = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(upstreamBytes),
      );
      const resource = parsed.action === "searchSchools"
        ? "schoolInfo"
        : "mealServiceDietInfo";
      const codes = [...new Set(resultCodes(upstreamJson, resource))];
      if (codes.length !== 1) {
        status = 502;
        return error(
          origin,
          status,
          "UPSTREAM_ERROR",
          "급식 정보를 불러오지 못했어요.",
        );
      }
      const [code] = codes;

      if (code === "INFO-300") {
        status = 429;
        return error(
          origin,
          status,
          "RATE_LIMITED",
          "요청이 많아요. 잠시 후 다시 시도해 주세요.",
        );
      }
      if (code === "INFO-200") {
        const response = noData(origin, parsed);
        status = response.status;
        return response;
      }
      if (code !== "INFO-000") {
        status = 502;
        return error(
          origin,
          status,
          "UPSTREAM_ERROR",
          "급식 정보를 불러오지 못했어요.",
        );
      }

      const upstreamRows = resourceRows(upstreamJson, resource);
      if (upstreamRows === null) {
        status = 502;
        return error(
          origin,
          status,
          "UPSTREAM_ERROR",
          "급식 정보를 불러오지 못했어요.",
        );
      }
      if (upstreamRows.length === 0) {
        const response = noData(origin, parsed);
        status = response.status;
        return response;
      }

      const data = parsed.action === "searchSchools"
        ? normalizeSchoolRows(upstreamRows as RawSchoolRow[])
        : normalizeMealRows(
          upstreamRows as RawMealRow[],
          parsed.payload.date,
        )[0];
      status = 200;
      return json(origin, status, { ok: true, data });
    } catch {
      status = 502;
      return error(
        origin,
        status,
        "UPSTREAM_ERROR",
        "급식 정보를 불러오지 못했어요.",
      );
    } finally {
      log(JSON.stringify({
        requestId,
        action,
        status,
        durationMs: Math.round(performance.now() - started),
      }));
    }
  };
}
