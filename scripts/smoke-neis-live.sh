#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import datetime as _dt


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def pass_(message):
    print(f"PASS: {message}")


def read_api_key():
    config_path = "Config.xcconfig"
    if not os.path.exists(config_path):
        fail("Config.xcconfig is missing; create it from Config.example.xcconfig")

    with open(config_path, "r", encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"^\s*NEIS_API_KEY\s*=\s*(.+?)\s*$", line)
            if match:
                key = match.group(1).strip()
                if key and key not in {"YOUR_KEY_HERE", "$(NEIS_API_KEY)"}:
                    return key
    fail("Config.xcconfig NEIS_API_KEY is missing or still a placeholder")


def fetch_json(path, params):
    base_url = f"https://open.neis.go.kr/hub/{path}"
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(f"{base_url}?{query}", headers={"User-Agent": "NaymNaymLevelUpReleaseSmoke/1.0"})
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status < 200 or response.status >= 300:
            fail(f"{path} returned HTTP {response.status}")
        payload = response.read()
    return json.loads(payload.decode("utf-8"))


def extract_rows(payload, root_key):
    if root_key in payload:
        sections = payload[root_key]
        rows = []
        for section in sections:
            rows.extend(section.get("row", []))
        return rows

    result = payload.get("RESULT")
    if result:
        code = result.get("CODE", "unknown")
        message = result.get("MESSAGE", "")
        fail(f"{root_key} returned NEIS result {code}: {message}")

    fail(f"{root_key} response did not include expected row section")


def last_day_of_month(year, month):
    if month == 12:
        next_month = _dt.date(year + 1, 1, 1)
    else:
        next_month = _dt.date(year, month + 1, 1)
    return next_month - _dt.timedelta(days=1)


api_key = read_api_key()
school_name = os.environ.get("NEIS_SMOKE_SCHOOL_NAME", "등촌고등학교")
meal_month = os.environ.get("NEIS_SMOKE_MEAL_MONTH", "202606")

if not re.match(r"^\d{6}$", meal_month):
    fail("NEIS_SMOKE_MEAL_MONTH must be YYYYMM")

school_payload = fetch_json(
    "schoolInfo",
    {
        "KEY": api_key,
        "Type": "json",
        "pIndex": "1",
        "pSize": "100",
        "SCHUL_NM": school_name,
    },
)
school_rows = extract_rows(school_payload, "schoolInfo")
selected = next((row for row in school_rows if row.get("SCHUL_NM") == school_name), None)
if not selected:
    fail(f"schoolInfo returned no exact row for {school_name}")

office_code = selected.get("ATPT_OFCDC_SC_CODE", "")
school_code = selected.get("SD_SCHUL_CODE", "")
resolved_name = selected.get("SCHUL_NM", "")
if not office_code or not school_code:
    fail("schoolInfo row is missing officeCode or schoolCode")

pass_(f"schoolInfo resolved {resolved_name} officeCode={office_code} schoolCode={school_code}")

year = int(meal_month[:4])
month = int(meal_month[4:])
start = f"{year:04d}{month:02d}01"
end = last_day_of_month(year, month).strftime("%Y%m%d")
meal_payload = fetch_json(
    "mealServiceDietInfo",
    {
        "KEY": api_key,
        "Type": "json",
        "pIndex": "1",
        "pSize": "100",
        "ATPT_OFCDC_SC_CODE": office_code,
        "SD_SCHUL_CODE": school_code,
        "MMEAL_SC_CODE": "2",
        "MLSV_FROM_YMD": start,
        "MLSV_TO_YMD": end,
    },
)
meal_rows = extract_rows(meal_payload, "mealServiceDietInfo")
if not meal_rows:
    fail(f"mealServiceDietInfo returned no lunch rows for {resolved_name} {meal_month}")

first = meal_rows[0]
required_fields = ["MLSV_YMD", "DDISH_NM", "CAL_INFO", "NTR_INFO"]
missing = [field for field in required_fields if not first.get(field)]
if missing:
    fail(f"mealServiceDietInfo first row is missing required fields: {', '.join(missing)}")

pass_(f"mealServiceDietInfo returned {len(meal_rows)} lunch rows for {resolved_name} {meal_month}")
pass_("first meal row includes MLSV_YMD, DDISH_NM, CAL_INFO, NTR_INFO")
PY
