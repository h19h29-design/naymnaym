#!/usr/bin/env python3
import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "contracts" / "native-rebuild" / "v1"

EXPECTED_ARRAYS = {
    "userRoles": ["child", "parent"],
    "eatingStatuses": [
        "oneBite",
        "finished",
        "half",
        "smelledOnly",
        "difficultToday",
        "allergyAvoided",
    ],
    "recordableEatingStatuses": [
        "oneBite",
        "finished",
        "smelledOnly",
        "difficultToday",
        "allergyAvoided",
    ],
    "syncStates": ["localOnly", "queued", "synced", "failed", "deleted"],
    "motionStates": [
        "idle",
        "tapReaction",
        "mealSuccess",
        "levelUp",
        "comfort",
        "reducedMotion",
    ],
}
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


def load_json(path):
    try:
        with path.open(encoding="utf-8") as file:
            return json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{path.relative_to(ROOT)}: {error}") from error


def normalize_menu_name(menu_name):
    if not isinstance(menu_name, str):
        raise ValueError("fixture menuName must be a string")
    return menu_name.strip()


def validate_contract(contract):
    if not isinstance(contract, dict):
        return ["domain-contract.json: root must be an object"]

    errors = []
    if contract.get("version") != 1:
        errors.append("domain-contract.json: version must be exactly 1")

    for name, expected in EXPECTED_ARRAYS.items():
        value = contract.get(name)
        if not isinstance(value, list):
            errors.append(f"domain-contract.json: {name} must be an array")
            continue
        if not all(isinstance(item, str) for item in value):
            errors.append(f"domain-contract.json: {name} values must be strings")
        elif len(value) != len(set(value)):
            errors.append(f"domain-contract.json: {name} values must be unique")
        if value != expected:
            errors.append(f"domain-contract.json: {name} must match the exact v1 values")

    if contract.get("identityRules") != EXPECTED_IDENTITY_RULES:
        errors.append("domain-contract.json: identityRules must match the exact v1 rules")
    return errors


def validate_fixtures(fixtures, eating_statuses):
    if not isinstance(fixtures, dict):
        return ["domain-fixtures.json: root must be an object"]

    errors = []
    if fixtures.get("version") != 1:
        errors.append("domain-fixtures.json: version must be exactly 1")

    records = fixtures.get("recordIdentities")
    if not isinstance(records, list):
        return errors + ["domain-fixtures.json: recordIdentities must be an array"]
    if not records:
        errors.append("domain-fixtures.json: recordIdentities must not be empty")
    if records != EXPECTED_RECORD_IDENTITIES:
        errors.append("domain-fixtures.json: recordIdentities must match the exact v1 fixtures")

    expected_identities = []
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            errors.append(f"domain-fixtures.json: recordIdentities[{index}] must be an object")
            continue
        date = record.get("date")
        status = record.get("status")
        expected = record.get("expected")
        if not isinstance(date, str) or not date:
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].date must be a non-empty string")
            continue
        if status not in eating_statuses:
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].status must be an eating status")
            continue
        if not isinstance(expected, str):
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].expected must be a string")
            continue
        try:
            actual = f"{date}|{normalize_menu_name(record.get('menuName'))}|{status}"
        except ValueError as error:
            errors.append(f"domain-fixtures.json: recordIdentities[{index}]: {error}")
            continue
        if expected != actual:
            errors.append(
                f"domain-fixtures.json: recordIdentities[{index}].expected must be {actual!r}"
            )
        expected_identities.append(expected)

    if len(expected_identities) != len(set(expected_identities)):
        errors.append("domain-fixtures.json: record identity expectations must be unique")
    return errors


def main():
    try:
        contract = load_json(CONTRACTS / "domain-contract.json")
        fixtures = load_json(CONTRACTS / "domain-fixtures.json")
    except ValueError as error:
        print(f"native-rebuild-contract-validation: FAIL\n{error}", file=sys.stderr)
        return 1

    errors = validate_contract(contract)
    errors.extend(validate_fixtures(fixtures, contract.get("eatingStatuses", [])))
    if errors:
        print("native-rebuild-contract-validation: FAIL", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("native-rebuild-contract-validation: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
