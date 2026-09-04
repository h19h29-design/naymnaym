import { assertEquals } from "jsr:@std/assert@1";
import { createServerHandler } from "./server.ts";

Deno.test("exposes only a small unauthenticated health response", async () => {
  let businessCalls = 0;
  const handler = createServerHandler(() => {
    businessCalls++;
    return new Response("unexpected");
  });

  const response = await handler(new Request("http://localhost/health"));

  assertEquals(response.status, 200);
  assertEquals(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("x-content-type-options"), "nosniff");
  assertEquals(await response.json(), { ok: true });
  assertEquals(businessCalls, 0);
});

Deno.test("delegates only the root path to the protected business handler", async () => {
  let delegatedUrl = "";
  const handler = createServerHandler((request) => {
    delegatedUrl = request.url;
    return new Response("protected", { status: 403 });
  });

  const root = await handler(new Request("http://localhost/"));
  const missing = await handler(new Request("http://localhost/other"));
  const invalidHealth = await handler(
    new Request("http://localhost/health", {
      method: "POST",
    }),
  );

  assertEquals(root.status, 403);
  assertEquals(await root.text(), "protected");
  assertEquals(delegatedUrl, "http://localhost/");
  assertEquals(missing.status, 404);
  assertEquals(invalidHealth.status, 405);
});
