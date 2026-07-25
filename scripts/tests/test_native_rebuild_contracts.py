import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts/native-rebuild/v1"

EXPECTED_IDENTITY_RULES = {
    "dateFormat": "yyyy-MM-dd",
    "normalizedMenuName": "trimAndLowercase",
    "recordIdentityComponents": ["date", "normalizedMenuName", "status"],
    "recordIdentity": "{date}|{normalizedMenuName}|{status}",
    "progressEventIdentity": "meal:{recordIdentity}",
    "progressEventSourceRecordIdentity": "{recordIdentity}",
}
EXPECTED_RECORD_IDENTITIES = [
    {
        "date": "2026-07-25",
        "menuName": " 시금치 나물 ",
        "status": "oneBite",
        "expected": "2026-07-25|시금치 나물|oneBite",
    },
    {
        "date": "2026-07-25",
        "menuName": "현미밥",
        "status": "finished",
        "expected": "2026-07-25|현미밥|finished",
    },
]


class NativeRebuildContractTests(unittest.TestCase):
    def test_xp_policy_preserves_existing_values(self):
        policy = json.loads((CONTRACTS / "xp-policy.json").read_text())

        self.assertEqual(policy["statusXP"], {
            "finished": 10,
            "half": 12,
            "oneBite": 18,
            "smelledOnly": 10,
            "difficultToday": 3,
            "allergyAvoided": 8,
        })
        self.assertEqual(policy["caps"], {"base": 50, "challengeBonus": 70, "total": 100})
        self.assertEqual(
            policy["activeStatuses"],
            ["oneBite", "finished", "smelledOnly", "difficultToday", "allergyAvoided"],
        )
        self.assertEqual(policy["legacyReadCompatibleStatuses"], ["half"])
        self.assertEqual(
            policy["awardIdentityComponents"],
            ["date", "normalizedMenuName"],
        )
        self.assertEqual(
            policy["awardIdentity"],
            "{date}|{normalizedMenuName}",
        )
        self.assertIs(policy["statusTransitionsGrantAdditionalXP"], False)

    def test_validator_rejects_xp_policy_that_allows_status_transition_farming(self):
        invalid_mutations = [
            {"awardIdentityComponents": ["date", "normalizedMenuName", "status"]},
            {"awardIdentity": "{date}|{normalizedMenuName}|{status}"},
            {"statusTransitionsGrantAdditionalXP": True},
        ]

        for mutation in invalid_mutations:
            with self.subTest(mutation=mutation):
                policy = json.loads((CONTRACTS / "xp-policy.json").read_text())
                policy.update(mutation)

                result = self._run_validator_with(xp_policy=policy)

                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("xp-policy.json", result.stderr)

    def test_nutrition_fixture_is_deterministic(self):
        fixtures = json.loads((CONTRACTS / "meal-loop-fixtures.json").read_text())
        rules = json.loads((CONTRACTS / "nutrition-rules.json").read_text())

        expected_nutrients = {
            "시금치나물": ["fiber", "vitamin"],
            "닭고기": ["protein", "iron"],
            "우유": ["calcium"],
            "현미밥": ["carbohydrate"],
            "알 수 없는 메뉴": [],
        }
        self.assertEqual(
            {item["menuName"]: item["nutrients"] for item in fixtures["nutrition"]},
            expected_nutrients,
        )
        self.assertEqual(fixtures["xpNearDailyCap"], {
            "usedBaseXP": 45,
            "status": "oneBite",
            "expectedGrantedXP": 5,
        })
        self.assertEqual(fixtures["duplicateEvent"], {
            "date": "2026-07-25",
            "menuName": " 시금치 나물 ",
            "normalizedMenuName": "시금치 나물",
            "status": "oneBite",
            "recordID": "2026-07-25|시금치 나물|oneBite",
            "eventID": "meal:2026-07-25|시금치 나물|oneBite",
            "duplicateEventID": "meal:2026-07-25|시금치 나물|oneBite",
            "expectedGrantedXP": 0,
        })
        self.assertEqual(rules["omissionCopy"], "영양소를 조금 놓칠 수 있어요.")
        self.assertIn("의학 진단이나 치료를 대신하지 않는", rules["educationNotice"])

    def test_validator_rejects_unsafe_or_ambiguous_meal_loop_contracts(self):
        policy = {
            "version": 1,
            "activeStatuses": ["oneBite", "finished", "half", "smelledOnly", "difficultToday"],
            "legacyReadCompatibleStatuses": ["half"],
            "statusXP": {
                "finished": 10,
                "half": 12,
                "oneBite": -18,
                "smelledOnly": 10,
                "difficultToday": 3,
                "allergyAvoided": 8,
            },
            "caps": {"base": 50, "challengeBonus": 70, "total": 100},
        }
        nutrition_rules = {
            "version": 1,
            "matching": "caseInsensitiveSubstring",
            "deduplicateNutrientIds": True,
            "educationNotice": "이 음식은 병을 치료해요.",
            "nutrientOrder": ["fiber", "fiber"],
            "nutrients": {
                "fiber": {"childName": "식이섬유", "alternatives": ["사과", "사과"]},
            },
            "rules": [{"keywords": ["나물", "나물"], "nutrients": ["fiber", "fiber"]}],
        }

        result = self._run_validator_with(
            xp_policy=policy,
            nutrition_rules=nutrition_rules,
        )

        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_rejects_malformed_nutrition_rule_without_a_traceback(self):
        nutrition_rules = json.loads((CONTRACTS / "nutrition-rules.json").read_text())
        nutrition_rules["rules"] = ["not a rule"]

        result = self._run_validator_with(nutrition_rules=nutrition_rules)

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("nutrition-rules.json: rules[0]", result.stderr)

    def test_validator_rejects_malformed_xp_policy_without_a_traceback(self):
        policy = json.loads((CONTRACTS / "xp-policy.json").read_text())
        policy["caps"] = {}

        result = self._run_validator_with(xp_policy=policy)

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("xp-policy.json: caps", result.stderr)

    def test_validator_rejects_malformed_or_noncanonical_duplicate_event_identity(self):
        invalid_mutations = [
            {"date": "2026-7-25"},
            {"status": "unknown"},
            {
                "status": "half",
                "recordID": "2026-07-25|시금치 나물|half",
                "eventID": "meal:2026-07-25|시금치 나물|half",
                "duplicateEventID": "meal:2026-07-25|시금치 나물|half",
            },
            {"menuName": "시금치 나물|oneBite"},
            {"recordID": "2026-07-25|시금치 나물|finished"},
            {"eventID": "meal:2026-07-25|시금치 나물|finished"},
            {"duplicateEventID": "meal:2026-07-25|시금치 나물|finished"},
        ]
        for mutations in invalid_mutations:
            with self.subTest(mutations=mutations):
                fixtures = json.loads((CONTRACTS / "meal-loop-fixtures.json").read_text())
                fixtures["duplicateEvent"].update(mutations)

                result = self._run_validator_with(meal_loop_fixtures=fixtures)

                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertIn("duplicateEvent", result.stderr)

    def test_validator_rejects_non_string_xp_fixture_status_without_a_traceback(self):
        fixtures = json.loads((CONTRACTS / "meal-loop-fixtures.json").read_text())
        fixtures["xpNearDailyCap"]["status"] = 18

        result = self._run_validator_with(meal_loop_fixtures=fixtures)

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("xpNearDailyCap status", result.stderr)

    def test_contract_has_exact_v1_values(self):
        contract = json.loads((CONTRACTS / "domain-contract.json").read_text())
        self.assertEqual(contract["version"], 1)
        self.assertEqual(contract["userRoles"], ["child", "parent"])
        self.assertEqual(contract["eatingStatuses"], [
            "oneBite", "finished", "half", "smelledOnly", "difficultToday", "allergyAvoided"
        ])
        self.assertEqual(contract["recordableEatingStatuses"], [
            "oneBite", "finished", "smelledOnly", "difficultToday", "allergyAvoided"
        ])
        self.assertEqual(contract["syncStates"], ["localOnly", "queued", "synced", "failed", "deleted"])
        self.assertEqual(contract["motionStates"], [
            "idle", "tapReaction", "mealSuccess", "levelUp", "comfort", "reducedMotion"
        ])
        self.assertEqual(contract["identityRules"], EXPECTED_IDENTITY_RULES)

    def test_fixtures_have_exact_v1_identity_vectors(self):
        fixtures = json.loads((CONTRACTS / "domain-fixtures.json").read_text())
        self.assertEqual(fixtures["version"], 1)
        self.assertEqual(fixtures["recordIdentities"], EXPECTED_RECORD_IDENTITIES)

    def test_validator_accepts_committed_contracts(self):
        result = subprocess.run(
            ["python3", "scripts/validate-native-rebuild-contracts.py"],
            cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_validator_rejects_self_consistent_non_v1_fixture_records(self):
        result = self._run_validator_with(
            fixtures={
                "version": 1,
                "recordIdentities": [
                    {
                        "date": "2026-07-25",
                        "menuName": "다른 메뉴",
                        "status": "finished",
                        "expected": "2026-07-25|다른 메뉴|finished",
                    }
                ],
            }
        )
        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_exits_one_for_duplicate_contract_values(self):
        contract = json.loads((CONTRACTS / "domain-contract.json").read_text())
        contract["userRoles"] = ["child", "child"]
        result = self._run_validator_with(contract=contract)
        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_exits_one_for_malformed_contract_array(self):
        contract = json.loads((CONTRACTS / "domain-contract.json").read_text())
        contract["syncStates"] = "synced"
        result = self._run_validator_with(contract=contract)
        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_rejects_boolean_design_token_version(self):
        design_tokens = json.loads((CONTRACTS / "design-tokens.json").read_text())
        design_tokens["version"] = True

        result = self._run_validator_with(design_tokens=design_tokens)

        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_rejects_float_design_token_version(self):
        design_tokens = json.loads((CONTRACTS / "design-tokens.json").read_text())
        design_tokens["version"] = 1.0

        result = self._run_validator_with(design_tokens=design_tokens)

        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_rejects_float_minimum_action_size(self):
        design_tokens = json.loads((CONTRACTS / "design-tokens.json").read_text())
        design_tokens["minimumActionSize"] = 48.0

        result = self._run_validator_with(design_tokens=design_tokens)

        self.assertEqual(result.returncode, 1, result.stderr)

    def test_validator_rejects_float_members_in_integer_token_arrays(self):
        for field in ("spacing", "radii"):
            with self.subTest(field=field):
                design_tokens = json.loads((CONTRACTS / "design-tokens.json").read_text())
                design_tokens[field][0] = float(design_tokens[field][0])

                result = self._run_validator_with(design_tokens=design_tokens)

                self.assertEqual(result.returncode, 1, result.stderr)

    def test_sync_copies_all_json_and_preserves_non_json_files(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = self._make_sync_project(pathlib.Path(temporary_directory))
            source = project / "contracts/native-rebuild/v1"
            extra_source = source / "additional-contract.json"
            extra_source.write_text('{"version": 1}\n', encoding="utf-8")

            destinations = [
                project / "NaymNaymLevelUp/Resources/RebuildContracts",
                project / "android/app/src/main/assets/rebuild-contracts",
            ]
            for destination in destinations:
                destination.mkdir(parents=True)
                (destination / "stale-contract.json").write_text("stale\n", encoding="utf-8")
                (destination / "keep.txt").write_text("keep\n", encoding="utf-8")

            result = self._run_sync(project)
            self.assertEqual(result.returncode, 0, result.stderr)
            source_hashes = {
                source_file.name: self._sha256(source_file) for source_file in source.glob("*.json")
            }
            for destination in destinations:
                self.assertFalse((destination / "stale-contract.json").exists())
                self.assertEqual((destination / "keep.txt").read_text(encoding="utf-8"), "keep\n")
                self.assertEqual(
                    {path.name: self._sha256(path) for path in destination.glob("*.json")},
                    source_hashes,
                )

    def test_sync_rejects_symlinked_destination_before_writing_outside_it(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = self._make_sync_project(pathlib.Path(temporary_directory))
            outside = project / "outside"
            outside.mkdir()
            destination = project / "NaymNaymLevelUp/Resources/RebuildContracts"
            destination.parent.mkdir(parents=True)
            destination.symlink_to(outside, target_is_directory=True)

            result = self._run_sync(project)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(outside.iterdir()), [])
            self.assertFalse((project / "android/app/src/main/assets/rebuild-contracts").exists())

    def test_sync_rejects_symlinked_json_target_before_mutating_any_destination(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = self._make_sync_project(pathlib.Path(temporary_directory))
            destination = project / "NaymNaymLevelUp/Resources/RebuildContracts"
            destination.mkdir(parents=True)
            outside_file = project / "outside-contract.json"
            outside_file.write_text("outside\n", encoding="utf-8")
            (destination / "domain-contract.json").symlink_to(outside_file)

            result = self._run_sync(project)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(outside_file.read_text(encoding="utf-8"), "outside\n")
            self.assertFalse((project / "android/app/src/main/assets/rebuild-contracts").exists())

    def _run_validator_with(
        self,
        contract=None,
        fixtures=None,
        design_tokens=None,
        nutrition_rules=None,
        xp_policy=None,
        meal_loop_fixtures=None,
    ):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = pathlib.Path(temporary_directory)
            shutil.copytree(CONTRACTS.parent, project / "contracts/native-rebuild")
            scripts = project / "scripts"
            scripts.mkdir()
            shutil.copy2(ROOT / "scripts/validate-native-rebuild-contracts.py", scripts)
            shutil.copy2(ROOT / "scripts/validate-mascot-rig.py", scripts)
            if contract is not None:
                (project / "contracts/native-rebuild/v1/domain-contract.json").write_text(
                    json.dumps(contract), encoding="utf-8"
                )
            if fixtures is not None:
                (project / "contracts/native-rebuild/v1/domain-fixtures.json").write_text(
                    json.dumps(fixtures), encoding="utf-8"
                )
            if design_tokens is not None:
                (project / "contracts/native-rebuild/v1/design-tokens.json").write_text(
                    json.dumps(design_tokens), encoding="utf-8"
                )
            if nutrition_rules is not None:
                (project / "contracts/native-rebuild/v1/nutrition-rules.json").write_text(
                    json.dumps(nutrition_rules), encoding="utf-8"
                )
            if xp_policy is not None:
                (project / "contracts/native-rebuild/v1/xp-policy.json").write_text(
                    json.dumps(xp_policy), encoding="utf-8"
                )
            if meal_loop_fixtures is not None:
                (project / "contracts/native-rebuild/v1/meal-loop-fixtures.json").write_text(
                    json.dumps(meal_loop_fixtures), encoding="utf-8"
                )
            return subprocess.run(
                [sys.executable, "scripts/validate-native-rebuild-contracts.py"],
                cwd=project,
                capture_output=True,
                text=True,
            )

    def _make_sync_project(self, project):
        shutil.copytree(CONTRACTS.parent, project / "contracts/native-rebuild")
        scripts = project / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts/sync-native-rebuild-contracts.sh", scripts)
        return project

    def _run_sync(self, project):
        return subprocess.run(
            ["bash", "scripts/sync-native-rebuild-contracts.sh"],
            cwd=project,
            capture_output=True,
            text=True,
        )

    def _sha256(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
