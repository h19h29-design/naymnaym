import { createHandler } from "./handler.ts";
import { resolveAllowedOrigins } from "./origin-config.ts";
import { createServerHandler } from "./server.ts";

const businessHandler = createHandler({
  allowedOrigins: resolveAllowedOrigins(Deno.env.get("NEIS_ALLOWED_ORIGINS")),
  neisApiKey: Deno.env.get("NEIS_API_KEY") ?? "",
  clientToken: Deno.env.get("NEIS_CLIENT_TOKEN") ?? "",
  fetch,
});

Deno.serve(
  { hostname: "0.0.0.0", port: 8000, onListen() {} },
  createServerHandler(businessHandler),
);
