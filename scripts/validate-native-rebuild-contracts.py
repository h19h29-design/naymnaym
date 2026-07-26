#!/usr/bin/env python3
import json
import pathlib
import datetime
import re
import runpy
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
EXPECTED_DESIGN_TOKENS = {
    "version": 1,
    "colors": {
        "forest700": "#1F5E43",
        "forest500": "#2F8A61",
        "leaf300": "#CBEA78",
        "cream50": "#FFF9EC",
        "cream100": "#F5EEDC",
        "ink900": "#183127",
        "muted600": "#627168",
        "danger700": "#A33A35",
    },
    "spacing": [4, 8, 12, 16, 24, 32],
    "radii": [12, 20, 28],
    "minimumActionSize": 48,
    "fontPolicy": "system-scalable",
}
EXPECTED_NUTRIENT_ORDER = ["fiber", "vitamin", "protein", "iron", "calcium", "carbohydrate"]
EXPECTED_NUTRITION_RULES = [
    {
        "keywords": ["나물", "시금치", "콩나물", "채소", "샐러드", "오이", "상추", "깻잎", "브로콜리"],
        "nutrients": ["fiber", "vitamin"],
    },
    {
        "keywords": ["닭", "돼지", "소", "고기", "생선", "계란", "달걀", "두부", "고등어", "멸치"],
        "nutrients": ["protein", "iron"],
    },
    {"keywords": ["우유", "멸치", "치즈", "요구르트", "요거트"], "nutrients": ["calcium"]},
    {"keywords": ["밥", "면", "빵", "떡", "잡채", "국수"], "nutrients": ["carbohydrate"]},
    {"keywords": ["김치", "과일", "토마토", "귤", "사과", "배추"], "nutrients": ["vitamin"]},
]
EXPECTED_NUTRIENTS = {
    "fiber": {"childName": "식이섬유", "alternatives": ["사과", "고구마"]},
    "vitamin": {"childName": "비타민", "alternatives": ["귤", "토마토"]},
    "protein": {"childName": "단백질", "alternatives": ["달걀", "두부"]},
    "iron": {"childName": "철분", "alternatives": ["소고기", "두부"]},
    "calcium": {"childName": "칼슘", "alternatives": ["우유", "멸치"]},
    "carbohydrate": {"childName": "탄수화물", "alternatives": ["밥", "고구마"]},
}
EXPECTED_STATUS_XP = {
    "finished": 10,
    "half": 12,
    "oneBite": 18,
    "smelledOnly": 10,
    "difficultToday": 3,
    "allergyAvoided": 8,
}
EXPECTED_CAPS = {"base": 50, "challengeBonus": 70, "total": 100}
EXPECTED_GROWTH_THRESHOLDS = [0, 80, 180, 320, 500, 720, 1000]
EXPECTED_GROWTH_TITLES = [
    "냠냠 새싹",
    "한 입 탐험가",
    "냠냠 용사",
    "편식 몬스터 사냥꾼",
    "급식 히어로",
    "영양 마스터",
    "레전드 냠냠러",
]
EXPECTED_FOREST_LAYER_ORDER = [
    "sky",
    "distantTrees",
    "midgroundTrees",
    "foregroundLeaves",
    "ground",
]
EXPECTED_FOREST_KEYFRAMES = [
    {"elapsedMs": 0, "progress": 0.0},
    {"elapsedMs": 2000, "progress": 0.5},
    {"elapsedMs": 4000, "progress": 1.0},
    {"elapsedMs": 6000, "progress": 0.5},
    {"elapsedMs": 8000, "progress": 0.0},
]
EXPECTED_FOREST_MOTION = {
    "sky": {"x": 0.0, "y": 0.0},
    "distantTrees": {"x": 0.0, "y": -2.0},
    "midgroundTrees": {"x": 0.0, "y": -4.0},
    "foregroundLeaves": {"x": 6.0, "y": -3.0},
    "ground": {"x": 0.0, "y": 0.0},
}
EXPECTED_FOREST_MEMORY = {
    "forestDecodedBytes": 32060800,
    "activeMascotDecodedBytes": 18870192,
    "combinedDecodedBytes": 50930992,
    "forestLimitBytes": 33554432,
    "combinedLimitBytes": 54525952,
}
EXPECTED_FOREST_LAYERS = {
    "sky": {
        "masterFilename": "sky.png",
        "runtimeFilename": "forest_home_sky.png",
        "pngColorType": 2,
        "masterSha256": "0637af27204976fae7063dad80bbeceea6ac469a4d65ed6659f146ecc33b12d0",
        "runtimeSha256": "31269847c3ea3825cfb0622c642bbf7bf58cd85f49c168a4b77864cb134151c6",
    },
    "distantTrees": {
        "masterFilename": "distantTrees.png",
        "runtimeFilename": "forest_home_distant_trees.png",
        "pngColorType": 6,
        "masterSha256": "48e7598f0aa73b459ce4e0861e150945bbf08e464dfe4182a892ed91b407b576",
        "runtimeSha256": "9c2e598b7aaad3240a97930a796b499769950a3dcd3569e89fd728319d1e56f1",
    },
    "midgroundTrees": {
        "masterFilename": "midgroundTrees.png",
        "runtimeFilename": "forest_home_midground_trees.png",
        "pngColorType": 6,
        "masterSha256": "7c04b3032c359feed724fbbd4b102b315de67ca226bd274144c5d0a5168485c2",
        "runtimeSha256": "19cd4380674504a333c31573432562ab3e3cb8730e7f2283c15d0e8c0b3e2dbf",
    },
    "foregroundLeaves": {
        "masterFilename": "foregroundLeaves.png",
        "runtimeFilename": "forest_home_foreground_leaves.png",
        "pngColorType": 6,
        "masterSha256": "04429a2b8b69e59847cf69b8ed5d0b52342e9587143d113bf68a78bb529d587a",
        "runtimeSha256": "66893d6c0913a36962ec2b2855506bb26e47a0024bc65ceb662bf5b0e6759c28",
    },
    "ground": {
        "masterFilename": "ground.png",
        "runtimeFilename": "forest_home_ground.png",
        "pngColorType": 6,
        "masterSha256": "9d103ed0ec164fba18478a1f2d287541db2d7b48ac3ace0224dc42b19cefb5d1",
        "runtimeSha256": "5468374dce57202cec48e94e11015b339f15140b458b183320239f6653e8b23f",
    },
}
SAFE_EDUCATION_NOTICE = "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요."
CHILD_OMISSION_COPY = "영양소를 조금 놓칠 수 있어요."


def load_json(path):
    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key {key!r}")
            result[key] = value
        return result

    try:
        with path.open(encoding="utf-8") as file:
            return json.load(file, object_pairs_hook=reject_duplicate_keys)
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{path.relative_to(ROOT)}: {error}") from error


def normalize_menu_name(menu_name):
    if not isinstance(menu_name, str):
        raise ValueError("fixture menuName must be a string")
    return menu_name.strip().lower()


def is_canonical_date(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return False
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def record_identity(date, normalized_menu_name, status):
    return f"{date}|{normalized_menu_name}|{status}"


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
        if not is_canonical_date(date):
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].date must be yyyy-MM-dd")
            continue
        if status not in eating_statuses:
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].status must be an eating status")
            continue
        if not isinstance(expected, str):
            errors.append(f"domain-fixtures.json: recordIdentities[{index}].expected must be a string")
            continue
        try:
            normalized_menu_name = normalize_menu_name(record.get("menuName"))
            if not normalized_menu_name or "|" in normalized_menu_name:
                raise ValueError("fixture menuName must normalize to a non-empty pipe-free string")
            actual = record_identity(date, normalized_menu_name, status)
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


def matches_exact_json_types(actual, expected):
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(
            matches_exact_json_types(actual[key], value) for key, value in expected.items()
        )
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            matches_exact_json_types(actual_item, expected_item)
            for actual_item, expected_item in zip(actual, expected)
        )
    return actual == expected


def validate_design_tokens(tokens):
    if not matches_exact_json_types(tokens, EXPECTED_DESIGN_TOKENS):
        return ["design-tokens.json: must match the exact v1 content"]
    return []


def validate_forest_scene(scene):
    if not isinstance(scene, dict):
        return ["forest-scene.json: root must be an object"]
    expected = {
        "version": 1,
        "masterCanvas": {"width": 1290, "height": 2796},
        "runtimeCanvas": {"width": 860, "height": 1864},
        "layerOrder": EXPECTED_FOREST_LAYER_ORDER,
        "layers": EXPECTED_FOREST_LAYERS,
        "cycleDurationMs": 8000,
        "keyframes": EXPECTED_FOREST_KEYFRAMES,
        "motion": EXPECTED_FOREST_MOTION,
        "foregroundOverscanScale": 1.04,
        "pauseSources": ["sheet", "inactiveTab", "inactiveApp"],
        "reduceMotion": {
            "allTransformsZero": True,
            "schedulesFrameCallback": False,
        },
        "contentSurface": {
            "backgroundToken": "cream50",
            "foregroundTokens": ["ink900", "forest700", "muted600"],
        },
        "memory": EXPECTED_FOREST_MEMORY,
    }
    if not matches_exact_json_types(scene, expected):
        return ["forest-scene.json: must match the exact v1 scene contract"]
    return []


def is_integer(value):
    return type(value) is int


def validate_unique_strings(value, name, errors):
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        errors.append(f"{name} must be a non-empty string array")
        return False
    if len(value) != len(set(value)):
        errors.append(f"{name} values must be unique")
        return False
    return True


def estimate_nutrients(menu_name, rules):
    lowered = menu_name.lower()
    nutrients = []
    for rule in rules:
        if any(keyword in lowered for keyword in rule["keywords"]):
            for nutrient in rule["nutrients"]:
                if nutrient not in nutrients:
                    nutrients.append(nutrient)
    return nutrients


def validate_nutrition_rules(rules):
    if not isinstance(rules, dict):
        return ["nutrition-rules.json: root must be an object"]

    errors = []
    expected_keys = {
        "version", "matching", "deduplicateNutrientIds", "omissionCopy", "educationNotice", "nutrientOrder", "nutrients", "rules"
    }
    if set(rules) != expected_keys:
        errors.append("nutrition-rules.json: must contain only the v1 schema fields")
    if rules.get("version") != 1 or not is_integer(rules.get("version")):
        errors.append("nutrition-rules.json: version must be exactly integer 1")
    if rules.get("matching") != "caseInsensitiveSubstring":
        errors.append("nutrition-rules.json: matching must be caseInsensitiveSubstring")
    if rules.get("deduplicateNutrientIds") is not True:
        errors.append("nutrition-rules.json: deduplicateNutrientIds must be true")
    if rules.get("omissionCopy") != CHILD_OMISSION_COPY:
        errors.append("nutrition-rules.json: omissionCopy must use the child-facing '놓칠 수 있어요' wording")
    if rules.get("educationNotice") != SAFE_EDUCATION_NOTICE:
        errors.append("nutrition-rules.json: educationNotice must use the safe educational wording")

    nutrient_order = rules.get("nutrientOrder")
    if validate_unique_strings(nutrient_order, "nutrition-rules.json: nutrientOrder", errors):
        if nutrient_order != EXPECTED_NUTRIENT_ORDER:
            errors.append("nutrition-rules.json: nutrientOrder must match the exact v1 nutrient IDs")

    nutrients = rules.get("nutrients")
    if not isinstance(nutrients, dict):
        errors.append("nutrition-rules.json: nutrients must be an object")
    else:
        if list(nutrients) != EXPECTED_NUTRIENT_ORDER:
            errors.append("nutrition-rules.json: nutrients must use the deterministic v1 order")
        if nutrients != EXPECTED_NUTRIENTS:
            errors.append("nutrition-rules.json: nutrients must match the child-safe v1 alternatives")
        for nutrient_id, nutrient in nutrients.items():
            if not isinstance(nutrient, dict) or set(nutrient) != {"childName", "alternatives"}:
                errors.append(f"nutrition-rules.json: nutrients.{nutrient_id} must contain childName and alternatives")
                continue
            if not isinstance(nutrient["childName"], str) or not nutrient["childName"]:
                errors.append(f"nutrition-rules.json: nutrients.{nutrient_id}.childName must be a non-empty string")
            alternatives = nutrient["alternatives"]
            if validate_unique_strings(alternatives, f"nutrition-rules.json: nutrients.{nutrient_id}.alternatives", errors):
                if not 1 <= len(alternatives) <= 2:
                    errors.append(f"nutrition-rules.json: nutrients.{nutrient_id}.alternatives must contain one or two foods")

    keyword_rules = rules.get("rules")
    if not isinstance(keyword_rules, list):
        return errors + ["nutrition-rules.json: rules must be an array"]
    if keyword_rules != EXPECTED_NUTRITION_RULES:
        errors.append("nutrition-rules.json: rules must preserve the ordered iOS keyword rules")
    nutrient_ids = set(nutrients) if isinstance(nutrients, dict) else set()
    for index, rule in enumerate(keyword_rules):
        if not isinstance(rule, dict) or set(rule) != {"keywords", "nutrients"}:
            errors.append(f"nutrition-rules.json: rules[{index}] must contain keywords and nutrients")
            continue
        validate_unique_strings(rule["keywords"], f"nutrition-rules.json: rules[{index}].keywords", errors)
        if validate_unique_strings(rule["nutrients"], f"nutrition-rules.json: rules[{index}].nutrients", errors):
            unknown = set(rule["nutrients"]) - nutrient_ids
            if unknown:
                errors.append(f"nutrition-rules.json: rules[{index}] references unknown nutrient IDs")
    return errors


def validate_xp_policy(policy, eating_statuses, recordable_statuses):
    if not isinstance(policy, dict):
        return ["xp-policy.json: root must be an object"]

    errors = []
    if set(policy) != {
        "version",
        "activeStatuses",
        "legacyReadCompatibleStatuses",
        "awardIdentityComponents",
        "awardIdentity",
        "statusTransitionsGrantAdditionalXP",
        "statusXP",
        "caps",
    }:
        errors.append("xp-policy.json: must contain only the v1 schema fields")
    if policy.get("version") != 1 or not is_integer(policy.get("version")):
        errors.append("xp-policy.json: version must be exactly integer 1")

    active = policy.get("activeStatuses")
    legacy = policy.get("legacyReadCompatibleStatuses")
    active_is_valid = validate_unique_strings(active, "xp-policy.json: activeStatuses", errors)
    legacy_is_valid = validate_unique_strings(legacy, "xp-policy.json: legacyReadCompatibleStatuses", errors)
    if active_is_valid and active != recordable_statuses:
        errors.append("xp-policy.json: activeStatuses must match recordable eating statuses")
    if legacy_is_valid and legacy != ["half"]:
        errors.append("xp-policy.json: half is the only legacy read-compatible status")
    if active_is_valid and legacy_is_valid:
        if set(active) & set(legacy):
            errors.append("xp-policy.json: active and legacy statuses must not overlap")
        if set(active) | set(legacy) != set(eating_statuses):
            errors.append("xp-policy.json: active and legacy statuses must cover allowed eating statuses")
    if policy.get("awardIdentityComponents") != ["date", "normalizedMenuName"]:
        errors.append("xp-policy.json: awardIdentityComponents must exclude status")
    if policy.get("awardIdentity") != "{date}|{normalizedMenuName}":
        errors.append("xp-policy.json: awardIdentity must exclude status")
    if policy.get("statusTransitionsGrantAdditionalXP") is not False:
        errors.append("xp-policy.json: status transitions must not grant additional XP")

    status_xp = policy.get("statusXP")
    if not isinstance(status_xp, dict):
        errors.append("xp-policy.json: statusXP must be an object")
    else:
        if status_xp != EXPECTED_STATUS_XP:
            errors.append("xp-policy.json: statusXP must match the exact v1 rewards")
        if set(status_xp) != set(eating_statuses):
            errors.append("xp-policy.json: statusXP keys must be the allowed eating statuses")
        for status, xp in status_xp.items():
            if not is_integer(xp) or xp < 0:
                errors.append(f"xp-policy.json: statusXP.{status} must be a non-negative integer")

    caps = policy.get("caps")
    if not isinstance(caps, dict):
        errors.append("xp-policy.json: caps must be an object")
    else:
        if caps != EXPECTED_CAPS:
            errors.append("xp-policy.json: caps must match the exact v1 limits")
        if set(caps) != {"base", "challengeBonus", "total"}:
            errors.append("xp-policy.json: caps must contain base, challengeBonus, and total")
        elif not all(is_integer(value) and value >= 0 for value in caps.values()):
            errors.append("xp-policy.json: caps must be non-negative integers")
        elif caps["base"] > caps["total"] or caps["challengeBonus"] > caps["total"]:
            errors.append("xp-policy.json: component caps must not exceed total")
    return errors


def validate_growth_policy(policy):
    if not isinstance(policy, dict):
        return ["growth-policy.json: root must be an object"]

    errors = []
    if set(policy) != {"version", "thresholds", "titles"}:
        errors.append(
            "growth-policy.json: must contain only version, thresholds, and titles"
        )
    if policy.get("version") != 1 or not is_integer(policy.get("version")):
        errors.append("growth-policy.json: version must be exactly integer 1")

    thresholds = policy.get("thresholds")
    if thresholds != EXPECTED_GROWTH_THRESHOLDS:
        errors.append(
            "growth-policy.json: thresholds must match the exact shipped values"
        )
    if (
        not isinstance(thresholds, list)
        or len(thresholds) != 7
        or not all(is_integer(value) and value >= 0 for value in thresholds)
        or any(left >= right for left, right in zip(thresholds, thresholds[1:]))
    ):
        errors.append(
            "growth-policy.json: thresholds must be seven increasing non-negative integers"
        )

    titles = policy.get("titles")
    if titles != EXPECTED_GROWTH_TITLES:
        errors.append(
            "growth-policy.json: titles must match PlayerProgress.levelTitles"
        )
    if (
        not isinstance(titles, list)
        or len(titles) != 7
        or not all(isinstance(value, str) and value for value in titles)
        or len(set(titles)) != 7
    ):
        errors.append(
            "growth-policy.json: titles must be seven unique non-empty strings"
        )
    return errors


def validate_meal_loop_fixtures(fixtures, rules, policy):
    if not isinstance(fixtures, dict):
        return ["meal-loop-fixtures.json: root must be an object"]

    errors = []
    if set(fixtures) != {"version", "nutrition", "xpNearDailyCap", "duplicateEvent"}:
        errors.append("meal-loop-fixtures.json: must contain only the v1 schema fields")
    if fixtures.get("version") != 1 or not is_integer(fixtures.get("version")):
        errors.append("meal-loop-fixtures.json: version must be exactly integer 1")
    nutrition = fixtures.get("nutrition")
    expected_menus = ["시금치나물", "닭고기", "우유", "현미밥", "알 수 없는 메뉴"]
    if not isinstance(nutrition, list):
        errors.append("meal-loop-fixtures.json: nutrition must be an array")
    else:
        menu_names = []
        for index, fixture in enumerate(nutrition):
            if not isinstance(fixture, dict) or set(fixture) != {"menuName", "nutrients"}:
                errors.append(f"meal-loop-fixtures.json: nutrition[{index}] must contain menuName and nutrients")
                continue
            menu_name = fixture["menuName"]
            expected_nutrients = fixture["nutrients"]
            if not isinstance(menu_name, str) or not menu_name:
                errors.append(f"meal-loop-fixtures.json: nutrition[{index}].menuName must be a non-empty string")
                continue
            if not isinstance(expected_nutrients, list) or not all(isinstance(item, str) for item in expected_nutrients):
                errors.append(f"meal-loop-fixtures.json: nutrition[{index}].nutrients must be a string array")
                continue
            if len(expected_nutrients) != len(set(expected_nutrients)):
                errors.append(f"meal-loop-fixtures.json: nutrition[{index}].nutrients must be unique")
            rule_entries = rules.get("rules") if isinstance(rules, dict) else None
            can_estimate = isinstance(rule_entries, list) and all(
                isinstance(rule, dict)
                and set(rule) == {"keywords", "nutrients"}
                and isinstance(rule["keywords"], list)
                and all(isinstance(keyword, str) for keyword in rule["keywords"])
                and isinstance(rule["nutrients"], list)
                and all(isinstance(nutrient, str) for nutrient in rule["nutrients"])
                for rule in rule_entries
            )
            if can_estimate:
                if expected_nutrients != estimate_nutrients(menu_name, rule_entries):
                    errors.append(f"meal-loop-fixtures.json: nutrition[{index}] must match the ordered rules")
            menu_names.append(menu_name)
        if menu_names != expected_menus:
            errors.append("meal-loop-fixtures.json: nutrition must cover the deterministic v1 menu set")

    near_cap = fixtures.get("xpNearDailyCap")
    if not isinstance(near_cap, dict) or set(near_cap) != {"usedBaseXP", "status", "expectedGrantedXP"}:
        errors.append("meal-loop-fixtures.json: xpNearDailyCap must contain usedBaseXP, status, and expectedGrantedXP")
    elif not all(is_integer(near_cap[key]) for key in ("usedBaseXP", "expectedGrantedXP")):
        errors.append("meal-loop-fixtures.json: xpNearDailyCap XP values must be integers")
    elif not isinstance(near_cap["status"], str):
        errors.append("meal-loop-fixtures.json: xpNearDailyCap status must be a string")
    elif not isinstance(policy, dict):
        errors.append("meal-loop-fixtures.json: cannot validate XP fixture without a valid policy")
    else:
        status_xp = policy.get("statusXP")
        caps = policy.get("caps")
        active_statuses = policy.get("activeStatuses")
        can_apply_caps = (
            isinstance(status_xp, dict)
            and isinstance(caps, dict)
            and isinstance(active_statuses, list)
            and {"base", "challengeBonus", "total"}.issubset(caps)
            and all(is_integer(caps[key]) for key in ("base", "challengeBonus", "total"))
            and near_cap["status"] in status_xp
        )
        if not can_apply_caps:
            errors.append("meal-loop-fixtures.json: cannot validate XP fixture without a valid policy")
        elif near_cap["status"] not in active_statuses:
            errors.append("meal-loop-fixtures.json: xpNearDailyCap status must be active")
        elif near_cap["usedBaseXP"] < 0 or near_cap["usedBaseXP"] >= caps["base"]:
            errors.append("meal-loop-fixtures.json: xpNearDailyCap must be immediately below the base cap")
        elif near_cap["expectedGrantedXP"] != min(
            status_xp[near_cap["status"]], caps["base"] - near_cap["usedBaseXP"]
        ):
            errors.append("meal-loop-fixtures.json: xpNearDailyCap expectedGrantedXP must apply the base cap")

    duplicate = fixtures.get("duplicateEvent")
    duplicate_keys = {
        "date", "menuName", "normalizedMenuName", "status", "recordID", "eventID", "duplicateEventID", "expectedGrantedXP"
    }
    if not isinstance(duplicate, dict) or set(duplicate) != duplicate_keys:
        errors.append("meal-loop-fixtures.json: duplicateEvent must contain canonical record and event identity components")
    elif not all(isinstance(duplicate[key], str) for key in duplicate_keys - {"expectedGrantedXP"}):
        errors.append("meal-loop-fixtures.json: duplicateEvent identity components must be strings")
    elif not is_canonical_date(duplicate["date"]):
        errors.append("meal-loop-fixtures.json: duplicateEvent date must be yyyy-MM-dd")
    elif not isinstance(policy, dict) or not isinstance(policy.get("activeStatuses"), list):
        errors.append("meal-loop-fixtures.json: cannot validate duplicateEvent without active XP statuses")
    elif duplicate["status"] not in policy["activeStatuses"]:
        errors.append("meal-loop-fixtures.json: duplicateEvent status must be an active eating status")
    else:
        normalized_menu_name = normalize_menu_name(duplicate["menuName"])
        if not normalized_menu_name or "|" in normalized_menu_name:
            errors.append("meal-loop-fixtures.json: duplicateEvent menuName must normalize to a non-empty pipe-free string")
        elif duplicate["normalizedMenuName"] != normalized_menu_name:
            errors.append("meal-loop-fixtures.json: duplicateEvent normalizedMenuName must be canonical")
        else:
            expected_record_id = record_identity(
                duplicate["date"], duplicate["normalizedMenuName"], duplicate["status"]
            )
            expected_event_id = f"meal:{expected_record_id}"
            if duplicate["recordID"] != expected_record_id:
                errors.append("meal-loop-fixtures.json: duplicateEvent recordID must use the canonical identity")
            if duplicate["eventID"] != expected_event_id:
                errors.append("meal-loop-fixtures.json: duplicateEvent eventID must prefix the canonical recordID")
            if duplicate["duplicateEventID"] != expected_event_id:
                errors.append("meal-loop-fixtures.json: duplicateEvent must reuse the canonical eventID")
        if not is_integer(duplicate["expectedGrantedXP"]) or duplicate["expectedGrantedXP"] != 0:
            errors.append("meal-loop-fixtures.json: duplicateEvent must grant zero XP")
    return errors


def main():
    try:
        contract = load_json(CONTRACTS / "domain-contract.json")
        fixtures = load_json(CONTRACTS / "domain-fixtures.json")
        design_tokens = load_json(CONTRACTS / "design-tokens.json")
        nutrition_rules = load_json(CONTRACTS / "nutrition-rules.json")
        xp_policy = load_json(CONTRACTS / "xp-policy.json")
        meal_loop_fixtures = load_json(CONTRACTS / "meal-loop-fixtures.json")
        mascot_rig = load_json(CONTRACTS / "mascot-rig.json")
        mascot_motion = load_json(CONTRACTS / "mascot-motion.json")
        growth_policy = load_json(CONTRACTS / "growth-policy.json")
        forest_scene = load_json(CONTRACTS / "forest-scene.json")
    except ValueError as error:
        print(f"native-rebuild-contract-validation: FAIL\n{error}", file=sys.stderr)
        return 1

    errors = validate_contract(contract)
    errors.extend(validate_fixtures(fixtures, contract.get("eatingStatuses", [])))
    errors.extend(validate_design_tokens(design_tokens))
    errors.extend(validate_nutrition_rules(nutrition_rules))
    errors.extend(validate_xp_policy(
        xp_policy,
        contract.get("eatingStatuses", []),
        contract.get("recordableEatingStatuses", []),
    ))
    errors.extend(validate_meal_loop_fixtures(meal_loop_fixtures, nutrition_rules, xp_policy))
    errors.extend(validate_growth_policy(growth_policy))
    errors.extend(validate_forest_scene(forest_scene))
    mascot_validator = runpy.run_path(
        str(ROOT / "scripts/validate-mascot-rig.py")
    )
    errors.extend(
        mascot_validator["validate_specs"](
            mascot_rig,
            mascot_motion,
            contract.get("motionStates", []),
        )
    )
    if errors:
        print("native-rebuild-contract-validation: FAIL", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("native-rebuild-contract-validation: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
