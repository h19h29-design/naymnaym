const DEFAULT_ALLOWED_ORIGINS = [
  "https://nyam-levelup.apps.tossmini.com",
  "https://nyam-levelup.private-apps.tossmini.com",
] as const;

export function resolveAllowedOrigins(
  configuredOrigins: string | undefined,
): Set<string> {
  const configured = (configuredOrigins ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);

  return new Set(
    configured.length > 0 ? configured : DEFAULT_ALLOWED_ORIGINS,
  );
}
