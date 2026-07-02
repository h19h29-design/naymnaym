import { createClient } from "npm:@supabase/supabase-js@2.45.4";

type SharingPermission = {
  shareEatingRecords: boolean;
  shareChallengeRecords: boolean;
  shareAllergyWarnings: boolean;
  sharePhotos: boolean;
};

type ChildLinkDTO = {
  id: string;
  childNickname: string;
  schoolName: string;
  officeCode: string;
  schoolCode: string;
  regionName: string;
  mode: "elementary" | "middle" | "high" | "parent";
  inviteCode: string;
  permissions: SharingPermission;
  createdAt: string;
  registeredAt?: string | null;
};

type MealRecordDTO = {
  id: string;
  date: string;
  menuName: string;
  eatingStatus: string;
  difficultyReasons: string[];
  allergyCodes: number[];
  photoIds: string[];
  createdAt: string;
};

type ChallengeRecordDTO = {
  id: string;
  date: string;
  menuName: string;
  action: string;
  gainedExp: number;
  badgeName?: string | null;
  nutrients: string[];
  createdAt: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = resolveServiceRoleKey();
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ ok: false, code: "method_not_allowed", error: "POST만 사용할 수 있어요." }, 405);
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ ok: false, code: "server_not_configured", error: "부모 연결 서버 설정이 완료되지 않았어요." }, 500);
  }

  const body = await safeJson(req);
  const action = typeof body?.action === "string" ? body.action : "";
  const payload = body?.payload ?? {};

  try {
    switch (action) {
      case "health":
        return json({ ok: true, data: { status: "ok" } });
      case "registerInvite":
        return await registerInvite(payload);
      case "connectInvite":
        return await connectInvite(payload);
      case "fetchSnapshot":
        return await fetchSnapshot(payload);
      case "publishSnapshot":
        return await publishSnapshot(payload);
      default:
        return json({ ok: false, code: "unknown_action", error: "지원하지 않는 요청이에요." }, 400);
    }
  } catch (error) {
    console.error("parent-sync error", error);
    return json({ ok: false, code: "server_error", error: "부모 연결 서버 처리 중 오류가 발생했어요." }, 500);
  }
});

async function registerInvite(payload: Record<string, unknown>): Promise<Response> {
  const link = payload.link as ChildLinkDTO | undefined;
  const inviteSecret = asString(payload.inviteSecret);

  if (!link || !isValidUUID(link.id) || !isValidInviteCode(link.inviteCode) || inviteSecret.length < 32) {
    return json({ ok: false, code: "invalid_invite", error: "초대 코드 등록 정보가 올바르지 않아요." }, 400);
  }

  if (!link.officeCode || !link.schoolCode || !link.schoolName) {
    return json({ ok: false, code: "missing_school", error: "학교 정보가 없어 부모가 급식 메뉴를 볼 수 없어요." }, 400);
  }

  const { data: existingByCode, error: existingError } = await supabase
    .from("nyam_parent_links")
    .select("child_link_id")
    .eq("invite_code", link.inviteCode)
    .maybeSingle();

  if (existingError) {
    return json({ ok: false, code: "db_error", error: "초대 코드 중복 확인에 실패했어요." }, 500);
  }

  if (existingByCode && existingByCode.child_link_id !== link.id) {
    return json({ ok: false, code: "invite_code_conflict", error: "이미 사용 중인 초대 코드예요. 새 코드를 만들어 주세요." }, 409);
  }

  const registeredAt = new Date().toISOString();
  const row = {
    child_link_id: link.id,
    invite_code: link.inviteCode,
    invite_secret_hash: await sha256(inviteSecret),
    child_nickname: trimForStorage(link.childNickname, 40) || "아이",
    school_name: trimForStorage(link.schoolName, 80) || "학교 미설정",
    office_code: trimForStorage(link.officeCode, 12),
    school_code: trimForStorage(link.schoolCode, 20),
    region_name: trimForStorage(link.regionName ?? "", 30),
    mode: link.mode,
    share_eating_records: Boolean(link.permissions?.shareEatingRecords),
    share_challenge_records: Boolean(link.permissions?.shareChallengeRecords),
    share_allergy_warnings: Boolean(link.permissions?.shareAllergyWarnings),
    share_photos: Boolean(link.permissions?.sharePhotos),
    created_at: safeDate(link.createdAt),
    registered_at: registeredAt,
    updated_at: registeredAt,
  };

  const { data, error } = await supabase
    .from("nyam_parent_links")
    .upsert(row, { onConflict: "child_link_id" })
    .select()
    .single();

  if (error) {
    return json({ ok: false, code: "db_error", error: "초대 코드를 서버에 저장하지 못했어요." }, 500);
  }

  return json({ ok: true, data: { link: rowToLink(data) } });
}

async function connectInvite(payload: Record<string, unknown>): Promise<Response> {
  const inviteCode = asString(payload.inviteCode);
  const link = await findLinkByInviteCode(inviteCode);
  if (!link) {
    return json({ ok: false, code: "invite_code_not_found", error: "초대 코드를 찾지 못했어요." }, 404);
  }

  const snapshot = await loadSnapshot(link.child_link_id);
  return json({ ok: true, data: { link: rowToLink(link), snapshot } });
}

async function fetchSnapshot(payload: Record<string, unknown>): Promise<Response> {
  const childLinkId = asString(payload.childLinkId);
  const inviteCode = asString(payload.inviteCode);

  if (!isValidUUID(childLinkId)) {
    return json({ ok: false, code: "invalid_child_link", error: "아이 연결 정보가 올바르지 않아요." }, 400);
  }

  const link = await findLinkByInviteCode(inviteCode);
  if (!link || link.child_link_id !== childLinkId) {
    return json({ ok: false, code: "invite_code_not_found", error: "초대 코드를 찾지 못했어요." }, 404);
  }

  return json({ ok: true, data: { snapshot: await loadSnapshot(childLinkId) } });
}

async function publishSnapshot(payload: Record<string, unknown>): Promise<Response> {
  const childLinkId = asString(payload.childLinkId);
  const inviteSecret = asString(payload.inviteSecret);
  const mealRecords = Array.isArray(payload.mealRecords) ? payload.mealRecords as MealRecordDTO[] : [];
  const challengeRecords = Array.isArray(payload.challengeRecords) ? payload.challengeRecords as ChallengeRecordDTO[] : [];

  if (!isValidUUID(childLinkId) || inviteSecret.length < 32) {
    return json({ ok: false, code: "invalid_upload", error: "공유 기록 업로드 정보가 올바르지 않아요." }, 400);
  }

  if (mealRecords.length > 200 || challengeRecords.length > 200) {
    return json({ ok: false, code: "payload_too_large", error: "한 번에 공유할 수 있는 기록 수를 초과했어요." }, 413);
  }

  const { data: link, error } = await supabase
    .from("nyam_parent_links")
    .select("*")
    .eq("child_link_id", childLinkId)
    .maybeSingle();

  if (error) {
    return json({ ok: false, code: "db_error", error: "아이 연결 정보를 확인하지 못했어요." }, 500);
  }
  if (!link || link.invite_secret_hash !== await sha256(inviteSecret)) {
    return json({ ok: false, code: "upload_forbidden", error: "아이 기기에서만 공유 기록을 올릴 수 있어요." }, 403);
  }

  const mealRows = link.share_eating_records
    ? mealRecords.filter(isValidMealRecord).map((record) => ({
      child_link_id: childLinkId,
      record_id: record.id,
      meal_date: trimForStorage(record.date, 12),
      menu_name: trimForStorage(record.menuName, 80),
      eating_status: record.eatingStatus,
      difficulty_reasons: safeStringArray(record.difficultyReasons, 12, 40),
      allergy_codes: link.share_allergy_warnings ? safeNumberArray(record.allergyCodes, 20) : [],
      photo_ids: link.share_photos ? safeStringArray(record.photoIds, 20, 80) : [],
      created_at: safeDate(record.createdAt),
      updated_at: new Date().toISOString(),
    }))
    : [];

  const challengeRows = link.share_challenge_records
    ? challengeRecords.filter(isValidChallengeRecord).map((record) => ({
      child_link_id: childLinkId,
      record_id: record.id,
      challenge_date: trimForStorage(record.date, 12),
      menu_name: trimForStorage(record.menuName, 80),
      action: record.action,
      gained_exp: Math.max(0, Math.min(Number(record.gainedExp) || 0, 500)),
      badge_name: record.badgeName ? trimForStorage(record.badgeName, 50) : null,
      nutrients: safeStringArray(record.nutrients, 20, 40),
      created_at: safeDate(record.createdAt),
      updated_at: new Date().toISOString(),
    }))
    : [];

  const { error: deleteMealsError } = await supabase
    .from("nyam_parent_meal_records")
    .delete()
    .eq("child_link_id", childLinkId);
  if (deleteMealsError) {
    return json({ ok: false, code: "db_error", error: "기존 먹은 정도 기록을 정리하지 못했어요." }, 500);
  }

  const { error: deleteChallengesError } = await supabase
    .from("nyam_parent_challenge_records")
    .delete()
    .eq("child_link_id", childLinkId);
  if (deleteChallengesError) {
    return json({ ok: false, code: "db_error", error: "기존 도전 기록을 정리하지 못했어요." }, 500);
  }

  if (mealRows.length > 0) {
    const { error: insertMealsError } = await supabase.from("nyam_parent_meal_records").insert(mealRows);
    if (insertMealsError) {
      return json({ ok: false, code: "db_error", error: "먹은 정도 기록을 저장하지 못했어요." }, 500);
    }
  }

  if (challengeRows.length > 0) {
    const { error: insertChallengesError } = await supabase.from("nyam_parent_challenge_records").insert(challengeRows);
    if (insertChallengesError) {
      return json({ ok: false, code: "db_error", error: "한 입 도전 기록을 저장하지 못했어요." }, 500);
    }
  }

  return json({ ok: true, data: {} });
}

async function loadSnapshot(childLinkId: string) {
  const { data: meals, error: mealsError } = await supabase
    .from("nyam_parent_meal_records")
    .select("*")
    .eq("child_link_id", childLinkId)
    .order("created_at", { ascending: false })
    .limit(100);
  if (mealsError) throw mealsError;

  const { data: challenges, error: challengesError } = await supabase
    .from("nyam_parent_challenge_records")
    .select("*")
    .eq("child_link_id", childLinkId)
    .order("created_at", { ascending: false })
    .limit(100);
  if (challengesError) throw challengesError;

  return {
    mealRecords: (meals ?? []).map(rowToMealRecord),
    challengeRecords: (challenges ?? []).map(rowToChallengeRecord),
  };
}

async function findLinkByInviteCode(inviteCode: string) {
  if (!isValidInviteCode(inviteCode)) {
    return null;
  }
  const { data, error } = await supabase
    .from("nyam_parent_links")
    .select("*")
    .eq("invite_code", inviteCode)
    .maybeSingle();
  if (error) throw error;
  return data;
}

function rowToLink(row: Record<string, unknown>): ChildLinkDTO {
  return {
    id: asString(row.child_link_id),
    childNickname: asString(row.child_nickname),
    schoolName: asString(row.school_name),
    officeCode: asString(row.office_code),
    schoolCode: asString(row.school_code),
    regionName: asString(row.region_name),
    mode: asString(row.mode) as ChildLinkDTO["mode"],
    inviteCode: asString(row.invite_code),
    permissions: {
      shareEatingRecords: Boolean(row.share_eating_records),
      shareChallengeRecords: Boolean(row.share_challenge_records),
      shareAllergyWarnings: Boolean(row.share_allergy_warnings),
      sharePhotos: Boolean(row.share_photos),
    },
    createdAt: asString(row.created_at),
    registeredAt: asString(row.registered_at),
  };
}

function rowToMealRecord(row: Record<string, unknown>): MealRecordDTO {
  return {
    id: asString(row.record_id),
    date: asString(row.meal_date),
    menuName: asString(row.menu_name),
    eatingStatus: asString(row.eating_status),
    difficultyReasons: Array.isArray(row.difficulty_reasons) ? row.difficulty_reasons.map(String) : [],
    allergyCodes: Array.isArray(row.allergy_codes) ? row.allergy_codes.map(Number).filter(Number.isFinite) : [],
    photoIds: Array.isArray(row.photo_ids) ? row.photo_ids.map(String) : [],
    createdAt: asString(row.created_at),
  };
}

function rowToChallengeRecord(row: Record<string, unknown>): ChallengeRecordDTO {
  return {
    id: asString(row.record_id),
    date: asString(row.challenge_date),
    menuName: asString(row.menu_name),
    action: asString(row.action),
    gainedExp: Number(row.gained_exp) || 0,
    badgeName: row.badge_name ? asString(row.badge_name) : null,
    nutrients: Array.isArray(row.nutrients) ? row.nutrients.map(String) : [],
    createdAt: asString(row.created_at),
  };
}

function isValidMealRecord(record: MealRecordDTO): boolean {
  return isValidUUID(record.id) &&
    ["finished", "half", "oneBite", "smelledOnly", "difficultToday", "allergyAvoided"].includes(record.eatingStatus) &&
    trimForStorage(record.date, 12).length > 0 &&
    trimForStorage(record.menuName, 80).length > 0;
}

function isValidChallengeRecord(record: ChallengeRecordDTO): boolean {
  return isValidUUID(record.id) &&
    ["skipped", "oneBite", "alreadyEats"].includes(record.action) &&
    trimForStorage(record.date, 12).length > 0 &&
    trimForStorage(record.menuName, 80).length > 0;
}

function resolveServiceRoleKey(): string {
  const direct = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (direct) return direct;

  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!secretKeys) return "";

  try {
    const parsed = JSON.parse(secretKeys);
    return parsed.service_role ?? parsed.serviceRole ?? parsed.default ?? parsed.SUPABASE_SERVICE_ROLE_KEY ?? "";
  } catch {
    return "";
  }
}

async function safeJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    return await req.json();
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function isValidInviteCode(code: string): boolean {
  return /^NYAM-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/.test(code);
}

function isValidUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function trimForStorage(value: unknown, maxLength: number): string {
  return asString(value).trim().slice(0, maxLength);
}

function safeStringArray(value: unknown, maxItems: number, maxLength: number): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => trimForStorage(item, maxLength)).filter(Boolean).slice(0, maxItems);
}

function safeNumberArray(value: unknown, maxItems: number): number[] {
  if (!Array.isArray(value)) return [];
  return value
    .map(Number)
    .filter((number) => Number.isInteger(number) && number > 0 && number < 100)
    .slice(0, maxItems);
}

function safeDate(value: unknown): string {
  const date = new Date(asString(value));
  if (Number.isNaN(date.getTime())) {
    return new Date().toISOString();
  }
  return date.toISOString();
}

async function sha256(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
