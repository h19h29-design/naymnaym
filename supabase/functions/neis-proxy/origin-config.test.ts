import { assertEquals } from "jsr:@std/assert@1";

Deno.test("uses only the two confirmed Toss origins when no override is configured", async () => {
  const { resolveAllowedOrigins } = await import("./origin-config.ts");

  assertEquals([...resolveAllowedOrigins(undefined)].sort(), [
    "https://nyam-levelup.apps.tossmini.com",
    "https://nyam-levelup.private-apps.tossmini.com",
  ]);
  assertEquals([...resolveAllowedOrigins("   ")].sort(), [
    "https://nyam-levelup.apps.tossmini.com",
    "https://nyam-levelup.private-apps.tossmini.com",
  ]);
});

Deno.test("uses a non-empty environment override instead of widening the default allowlist", async () => {
  const { resolveAllowedOrigins } = await import("./origin-config.ts");

  assertEquals(
    [...resolveAllowedOrigins(
      " https://preview.example,https://production.example ",
    )].sort(),
    [
      "https://preview.example",
      "https://production.example",
    ],
  );
});
