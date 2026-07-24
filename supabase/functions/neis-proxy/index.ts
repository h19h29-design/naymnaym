import { createHandler } from "./handler.ts";

const allowedOrigins = new Set(
  (Deno.env.get("NEIS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
);
const neisApiKey = Deno.env.get("NEIS_API_KEY") ?? "";

Deno.serve(createHandler({
  allowedOrigins,
  neisApiKey,
  fetch,
}));
