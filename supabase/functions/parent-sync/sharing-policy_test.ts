import {
  canShareChallengeRecord,
  canShareChallengeRow,
  canShareMealRecord,
} from "./sharing-policy.ts";

const allEnabled = {
  share_eating_records: true,
  share_challenge_records: true,
  share_allergy_warnings: true,
};

Deno.test("allergy-only permission never exposes ordinary eating status", () => {
  const allergyOnly = {
    share_eating_records: false,
    share_challenge_records: false,
    share_allergy_warnings: true,
  };

  assertFalse(canShareMealRecord({ eatingStatus: "finished" }, allergyOnly));
  assertTrue(
    canShareMealRecord({ eatingStatus: "allergyAvoided" }, allergyOnly),
  );
});

Deno.test("challenge records follow the permission for their eating status", () => {
  const challengeOnly = {
    share_eating_records: false,
    share_challenge_records: true,
    share_allergy_warnings: false,
  };

  assertTrue(
    canShareChallengeRecord(
      { action: "oneBite", eatingStatus: "oneBite" },
      challengeOnly,
    ),
  );
  assertFalse(
    canShareChallengeRecord(
      { action: "alreadyEats", eatingStatus: "finished" },
      challengeOnly,
    ),
  );
  assertFalse(
    canShareChallengeRecord(
      { action: "skipped", eatingStatus: "allergyAvoided" },
      challengeOnly,
    ),
  );
});

Deno.test("disabling challenge sharing hides every challenge row", () => {
  const challengeDisabled = {
    share_eating_records: true,
    share_challenge_records: false,
    share_allergy_warnings: true,
  };

  assertFalse(
    canShareChallengeRecord(
      { action: "alreadyEats", eatingStatus: "finished" },
      challengeDisabled,
    ),
  );
  assertFalse(
    canShareChallengeRecord(
      { action: "skipped", eatingStatus: "allergyAvoided" },
      challengeDisabled,
    ),
  );
});

Deno.test("permission revocation hides already stored challenge rows", () => {
  const eatingRevoked = {
    ...allEnabled,
    share_eating_records: false,
  };
  const allergyRevoked = {
    ...allEnabled,
    share_allergy_warnings: false,
  };

  assertFalse(
    canShareChallengeRow(
      { action: "alreadyEats", eating_status: "finished" },
      eatingRevoked,
    ),
  );
  assertFalse(
    canShareChallengeRow(
      { action: "skipped", eating_status: "allergyAvoided" },
      allergyRevoked,
    ),
  );
});

Deno.test("ambiguous legacy skipped rows require every related permission", () => {
  assertTrue(canShareChallengeRow({ action: "skipped" }, allEnabled));
  assertFalse(
    canShareChallengeRow(
      { action: "skipped" },
      { ...allEnabled, share_allergy_warnings: false },
    ),
  );
});

function assertTrue(value: boolean): void {
  if (!value) throw new Error("Expected true");
}

function assertFalse(value: boolean): void {
  if (value) throw new Error("Expected false");
}
