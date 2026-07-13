type ParentSharingPermissions = Record<string, unknown>;

type MealRecordLike = {
  eatingStatus: string;
};

type MealRowLike = {
  eating_status?: unknown;
};

type ChallengeRecordLike = {
  action: string;
  eatingStatus?: string | null;
};

type ChallengeRowLike = {
  action?: unknown;
  eating_status?: unknown;
};

const eatingStatuses = new Set([
  "finished",
  "half",
  "oneBite",
  "smelledOnly",
  "difficultToday",
  "allergyAvoided",
]);

export function canShareMealRecord(
  record: MealRecordLike,
  permissions: ParentSharingPermissions,
): boolean {
  return canShareEatingStatus(record.eatingStatus, permissions);
}

export function canShareMealRow(
  row: MealRowLike,
  permissions: ParentSharingPermissions,
): boolean {
  return canShareEatingStatus(asString(row.eating_status), permissions);
}

export function canShareChallengeRecord(
  record: ChallengeRecordLike,
  permissions: ParentSharingPermissions,
): boolean {
  return canShareChallenge(
    record.action,
    record.eatingStatus,
    permissions,
  );
}

export function canShareChallengeRow(
  row: ChallengeRowLike,
  permissions: ParentSharingPermissions,
): boolean {
  return canShareChallenge(
    asString(row.action),
    asString(row.eating_status) || null,
    permissions,
  );
}

function canShareEatingStatus(
  status: string,
  permissions: ParentSharingPermissions,
): boolean {
  if (status === "allergyAvoided") {
    return Boolean(permissions.share_allergy_warnings);
  }
  if (status === "oneBite" || status === "smelledOnly") {
    return Boolean(permissions.share_challenge_records);
  }
  return eatingStatuses.has(status) &&
    Boolean(permissions.share_eating_records);
}

function canShareChallenge(
  action: string,
  eatingStatus: string | null | undefined,
  permissions: ParentSharingPermissions,
): boolean {
  if (!permissions.share_challenge_records) {
    return false;
  }

  if (eatingStatus && eatingStatuses.has(eatingStatus)) {
    return canShareEatingStatus(eatingStatus, permissions);
  }

  // Legacy rows did not persist eatingStatus. Keep their fallback fail-closed.
  if (action === "oneBite") {
    return true;
  }
  if (action === "alreadyEats") {
    return Boolean(permissions.share_eating_records);
  }
  if (action === "skipped") {
    return Boolean(permissions.share_eating_records) &&
      Boolean(permissions.share_allergy_warnings);
  }
  return false;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}
