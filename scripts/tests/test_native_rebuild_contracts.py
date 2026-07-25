import json
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class NativeRebuildContractTests(unittest.TestCase):
    def test_contract_has_exact_v1_values(self):
        contract = json.loads((ROOT / "contracts/native-rebuild/v1/domain-contract.json").read_text())
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

    def test_validator_accepts_committed_contracts(self):
        result = subprocess.run(
            ["python3", "scripts/validate-native-rebuild-contracts.py"],
            cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
