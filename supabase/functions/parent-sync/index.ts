import { createClient } from "npm:@supabase/supabase-js@2.45.4";

type SharingPermission = {
  shareEatingRecords: boolean;
  shareChallengeRecords: boolean;
  shareAllergyWarnings: boolean;
  sharePhotos?: boolean;
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

type ParentDeviceDTO = {
  device_token: string;
  environment: string;
};

type ApnsConfig = {
  teamId: string;
  keyId: string;
  privateKey: string;
  bundleId: string;
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
        return json({ ok: true, data: { status: "ok", apnsConfigured: Boolean(resolveApnsConfig()) } });
      case "registerInvite":
        return await registerInvite(payload);
      case "connectInvite":
        return await connectInvite(payload);
      case "fetchSnapshot":
        return await fetchSnapshot(payload);
      case "publishSnapshot":
        return await publishSnapshot(payload);
      case "registerParentDevice":
        return await registerParentDevice(payload);
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
    share_photos: false,
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

async function registerParentDevice(payload: Record<string, unknown>): Promise<Response> {
  const childLinkId = asString(payload.childLinkId);
  const inviteCode = asString(payload.inviteCode);
  const deviceToken = asString(payload.deviceToken).trim().toLowerCase();
  const environment = normalizeApnsEnvironment(payload.environment);

  if (!isValidUUID(childLinkId) || !isValidDeviceToken(deviceToken) || !environment) {
    return json({ ok: false, code: "invalid_parent_device", error: "부모 알림 기기 정보가 올바르지 않아요." }, 400);
  }

  const link = await findLinkByInviteCode(inviteCode);
  if (!link || link.child_link_id !== childLinkId) {
    return json({ ok: false, code: "invite_code_not_found", error: "초대 코드를 찾지 못했어요." }, 404);
  }

  const now = new Date().toISOString();
  const row = {
    child_link_id: childLinkId,
    device_token_hash: await sha256(`${environment}:${deviceToken}`),
    device_token: deviceToken,
    environment,
    platform: "ios",
    is_active: true,
    last_registered_at: now,
    created_at: now,
    updated_at: now,
  };

  const { error } = await supabase
    .from("nyam_parent_devices")
    .upsert(row, { onConflict: "child_link_id,device_token_hash" });

  if (error) {
    return json({ ok: false, code: "db_error", error: "부모 알림 기기를 등록하지 못했어요." }, 500);
  }

  return json({ ok: true, data: {} });
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
      photo_ids: [],
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

  const notification = await sendParentMealResultNotifications(link, mealRows, challengeRows);
  return json({ ok: true, data: { notification } });
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
      sharePhotos: false,
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
    photoIds: [],
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

async function sendParentMealResultNotifications(
  link: Record<string, unknown>,
  mealRows: Array<Record<string, unknown>>,
  challengeRows: Array<Record<string, unknown>>,
) {
  const latest = latestSharedRecord(mealRows, challengeRows);
  if (!latest) {
    return { attempted: 0, sent: 0, skipped: "no_shared_records" };
  }

  const signature = `${latest.kind}:${asString(latest.record.record_id)}:${asString(latest.record.created_at)}`;
  if (asString(link.last_notification_signature) === signature) {
    return { attempted: 0, sent: 0, skipped: "duplicate_snapshot" };
  }

  const childLinkId = asString(link.child_link_id);
  const { data: devices, error } = await supabase
    .from("nyam_parent_devices")
    .select("device_token, environment")
    .eq("child_link_id", childLinkId)
    .eq("is_active", true)
    .limit(20);

  if (error) throw error;
  const registeredDevices = (devices ?? []) as ParentDeviceDTO[];
  if (registeredDevices.length === 0) {
    return { attempted: 0, sent: 0, skipped: "no_parent_devices" };
  }

  const apnsConfig = resolveApnsConfig();
  if (!apnsConfig) {
    await markNotificationSignature(childLinkId, signature);
    return { attempted: registeredDevices.length, sent: 0, skipped: "apns_not_configured" };
  }

  const title = `${trimForStorage(link.child_nickname, 40) || "아이"}가 급식 결과를 올렸어요`;
  const body = notificationBody(latest);
  let sent = 0;
  for (const device of registeredDevices) {
    const didSend = await sendApnsNotification(apnsConfig, device, {
      aps: {
        alert: { title, body },
        sound: "default",
        "thread-id": childLinkId,
      },
      childLinkId,
      type: "meal-result",
    });
    if (didSend) sent += 1;
  }

  await markNotificationSignature(childLinkId, signature);
  return { attempted: registeredDevices.length, sent };
}

function latestSharedRecord(
  mealRows: Array<Record<string, unknown>>,
  challengeRows: Array<Record<string, unknown>>,
): { kind: string; record: Record<string, unknown> } | null {
  const candidates = [
    ...mealRows.map((record) => ({ kind: "meal", record })),
    ...challengeRows.map((record) => ({ kind: "challenge", record })),
  ];
  candidates.sort((lhs, rhs) => asString(rhs.record.created_at).localeCompare(asString(lhs.record.created_at)));
  return candidates[0] ?? null;
}

function notificationBody(latest: { kind: string; record: Record<string, unknown> }): string {
  const menuName = trimForStorage(latest.record.menu_name, 40) || "급식 메뉴";
  if (latest.kind === "meal") {
    return `${menuName}: ${eatingStatusTitle(asString(latest.record.eating_status))}`;
  }
  return `${menuName}: 한 입 도전 기록이 업데이트됐어요.`;
}

function eatingStatusTitle(status: string): string {
  switch (status) {
    case "finished":
      return "다 먹었어요";
    case "half":
      return "반 정도 먹었어요";
    case "oneBite":
      return "한 입 먹었어요";
    case "smelledOnly":
      return "냄새만 맡아봤어요";
    case "allergyAvoided":
      return "주의 메뉴를 안전하게 피했어요";
    case "difficultToday":
    default:
      return "오늘은 어려웠어요";
  }
}

async function markNotificationSignature(childLinkId: string, signature: string) {
  const { error } = await supabase
    .from("nyam_parent_links")
    .update({
      last_notification_signature: signature,
      last_notification_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("child_link_id", childLinkId);
  if (error) throw error;
}

function resolveApnsConfig(): ApnsConfig | null {
  const teamId = Deno.env.get("APNS_TEAM_ID")?.trim() ?? "";
  const keyId = Deno.env.get("APNS_KEY_ID")?.trim() ?? "";
  const rawPrivateKey = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
  const privateKey = rawPrivateKey.replace(/\\n/g, "\n").trim();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")?.trim() || "com.h19h29.naymnaymlevelup";
  if (!teamId || !keyId || !privateKey || !bundleId) return null;
  return { teamId, keyId, privateKey, bundleId };
}

async function sendApnsNotification(
  config: ApnsConfig,
  device: ParentDeviceDTO,
  payload: Record<string, unknown>,
): Promise<boolean> {
  const environment = normalizeApnsEnvironment(device.environment) ?? "production";
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const jwt = await makeApnsJwt(config);

  const response = await fetch(`https://${host}/3/device/${device.device_token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (response.ok) return true;

  let reason = "unknown";
  try {
    const body = await response.json();
    reason = asString(body?.reason) || reason;
  } catch {
    // Ignore malformed APNs error bodies; never log device tokens.
  }
  console.error("apns send failed", { status: response.status, reason });
  return false;
}

async function makeApnsJwt(config: ApnsConfig): Promise<string> {
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64Url(JSON.stringify({ iss: config.teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
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

function isValidDeviceToken(value: string): boolean {
  return /^[a-f0-9]{64,200}$/.test(value);
}

function normalizeApnsEnvironment(value: unknown): "sandbox" | "production" | null {
  const environment = asString(value).trim().toLowerCase();
  if (environment === "sandbox" || environment === "production") return environment;
  return null;
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
