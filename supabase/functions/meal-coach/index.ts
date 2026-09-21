import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { createMealCoachHandler, GO_MODEL, GO_URL } from "./handler.mjs";
import { createRemoteProviderResolver } from "./provider-config.mjs";

type ClaimInput = {
  subjectHash: string;
  day: string;
  requestHash: string;
  fingerprint: string;
};

type FinishInput = {
  subjectHash: string;
  day: string;
  requestHash: string;
  success: boolean;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const serviceRoleKey = resolveServiceRoleKey();
const providerKey = Deno.env.get("MEAL_COACH_GO_API_KEY")?.trim() ?? "";

// Optional remote provider config served from the operator NAS. Lets the
// operator rotate the provider key, switch model/endpoint, or disable AI by
// editing one JSON file instead of redeploying secrets.
const providerConfigUrl = Deno.env.get("MEAL_COACH_CONFIG_URL")?.trim() ?? "";
const providerConfigToken = Deno.env.get("MEAL_COACH_CONFIG_TOKEN")?.trim() ?? "";
const resolveProvider = createRemoteProviderResolver({
  configUrl: providerConfigUrl,
  configToken: providerConfigToken,
  fallback: { key: providerKey, url: GO_URL, model: GO_MODEL },
});

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const handler = createMealCoachHandler({
  providerKey,
  resolveProvider,
  claim: async (input: ClaimInput): Promise<string> => {
    if (!supabaseUrl || !serviceRoleKey) return "storage_unavailable";
    const { data, error } = await supabase.rpc("nyam_ai_claim_daily", {
      p_subject_hash: input.subjectHash,
      p_day: input.day,
      p_request_hash: input.requestHash,
      p_fingerprint: input.fingerprint,
    });
    if (error || typeof data !== "string") return "storage_unavailable";
    return data;
  },
  finish: async (input: FinishInput): Promise<void> => {
    if (!supabaseUrl || !serviceRoleKey) throw new Error("storage_unavailable");
    const { error } = await supabase.rpc("nyam_ai_finish_daily", {
      p_subject_hash: input.subjectHash,
      p_day: input.day,
      p_request_hash: input.requestHash,
      p_success: input.success,
    });
    if (error) throw new Error("storage_unavailable");
  },
});

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const result = await handler(request);
    const headers = new Headers(result.headers);
    Object.entries(corsHeaders).forEach(([key, value]) => headers.set(key, value));
    return new Response(result.body, {
      status: result.status,
      statusText: result.statusText,
      headers,
    });
  } catch {
    return Response.json(
      { error: "server_unavailable" },
      { status: 503, headers: { ...corsHeaders, "Cache-Control": "no-store" } },
    );
  }
});

function resolveServiceRoleKey(): string {
  const direct = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (direct) return direct;

  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!secretKeys) return "";
  try {
    const parsed = JSON.parse(secretKeys);
    return parsed.service_role ?? parsed.serviceRole ?? parsed.default ??
      parsed.SUPABASE_SERVICE_ROLE_KEY ?? "";
  } catch {
    return "";
  }
}
