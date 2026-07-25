import { createHandler } from "./handler.ts";
import { resolveAllowedOrigins } from "./origin-config.ts";

const allowedOrigins = resolveAllowedOrigins(
  Deno.env.get("NEIS_ALLOWED_ORIGINS"),
);
const neisApiKey = Deno.env.get("NEIS_API_KEY") ?? "";

Deno.serve(createHandler({
  allowedOrigins,
  neisApiKey,
  fetch,
}));
