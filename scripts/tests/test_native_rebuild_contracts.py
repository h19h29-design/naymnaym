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
    "recordIdentity": "{date}|{normalizedMenuName}|{status}",
    "progressEventIdentity": "meal:{recordIdentity}",
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

    def _run_validator_with(self, contract=None, fixtures=None):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = pathlib.Path(temporary_directory)
            shutil.copytree(CONTRACTS.parent, project / "contracts/native-rebuild")
            scripts = project / "scripts"
            scripts.mkdir()
            shutil.copy2(ROOT / "scripts/validate-native-rebuild-contracts.py", scripts)
            if contract is not None:
                (project / "contracts/native-rebuild/v1/domain-contract.json").write_text(
                    json.dumps(contract), encoding="utf-8"
                )
            if fixtures is not None:
                (project / "contracts/native-rebuild/v1/domain-fixtures.json").write_text(
                    json.dumps(fixtures), encoding="utf-8"
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
