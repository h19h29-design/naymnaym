#!/bin/sh
set -eu

ENV_FILE=${NEIS_PROXY_ENV_FILE:?NEIS_PROXY_ENV_FILE is required}
BASE_URL=${NEIS_PROXY_URL:-https://neis.h19h19.synology.me}
LIVE_ORIGIN=https://nyam-levelup.apps.tossmini.com
QR_ORIGIN=https://nyam-levelup.private-apps.tossmini.com

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

read_env() {
  sed -n "s/^$1=//p" "$ENV_FILE" | head -n 1
}

[ -f "$ENV_FILE" ] || fail "env file is missing"
[ "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")" = 600 ] ||
  fail "env file mode must be 600"

CLIENT_TOKEN=$(read_env NEIS_CLIENT_TOKEN)
ALLOWED_ORIGINS=$(read_env NEIS_ALLOWED_ORIGINS)
[ -n "$CLIENT_TOKEN" ] || fail "NEIS_CLIENT_TOKEN is missing"
[ -n "$(read_env NEIS_API_KEY)" ] || fail "NEIS_API_KEY is missing"
[ "$ALLOWED_ORIGINS" = "$LIVE_ORIGIN,$QR_ORIGIN" ] ||
  fail "NEIS_ALLOWED_ORIGINS does not match the verified origins"

TMP_DIR=$(mktemp -d)
chmod 700 "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

request() {
  origin=$1
  action=$2
  payload=$3
  output=$4
  printf '{"clientToken":"%s","request":{"action":"%s","payload":%s}}' \
    "$CLIENT_TOKEN" "$action" "$payload" |
    curl --silent --show-error --max-time 25 \
      --output "$output" --write-out '%{http_code}' \
      --request POST "$BASE_URL/" \
      --header "origin: $origin" \
      --header 'content-type: text/plain;charset=UTF-8' \
      --data-binary @-
}

health_status=$(curl --silent --show-error --max-time 10 \
  --output "$TMP_DIR/health.json" --write-out '%{http_code}' "$BASE_URL/health")
[ "$health_status" = 200 ] || fail "health returned HTTP $health_status"
jq -e '.ok == true and keys == ["ok"]' "$TMP_DIR/health.json" >/dev/null ||
  fail "health response shape is invalid"
pass "health"

for origin in "$LIVE_ORIGIN" "$QR_ORIGIN"; do
  curl --silent --show-error --max-time 10 --dump-header "$TMP_DIR/options.headers" \
    --output /dev/null --request OPTIONS "$BASE_URL/" --header "origin: $origin"
  grep -Eiq '^HTTP/[^ ]+ 204([[:space:]]|$)' "$TMP_DIR/options.headers" ||
    fail "OPTIONS did not return 204"
  tr -d '\r' < "$TMP_DIR/options.headers" > "$TMP_DIR/options.clean"
  grep -Fiqx "access-control-allow-origin: $origin" "$TMP_DIR/options.clean" ||
    fail "OPTIONS allow-origin mismatch"
done
pass "both verified OPTIONS origins"

wrong_status=$(request https://wrong.example searchSchools \
  '{"keyword":"등촌고등학교","schoolType":"high"}' "$TMP_DIR/wrong.json")
[ "$wrong_status" = 403 ] || fail "wrong Origin returned HTTP $wrong_status"
jq -e '.ok == false and .code == "FORBIDDEN_ORIGIN"' "$TMP_DIR/wrong.json" >/dev/null ||
  fail "wrong Origin response is invalid"
pass "wrong Origin denied"

school_status=$(request "$LIVE_ORIGIN" searchSchools \
  '{"keyword":"등촌고등학교","schoolType":"high"}' "$TMP_DIR/school.json")
[ "$school_status" = 200 ] || fail "school search returned HTTP $school_status"
jq -e '.ok == true and any(.data[]; .name == "등촌고등학교" and .officeCode == "B10" and .schoolCode == "7010700")' \
  "$TMP_DIR/school.json" >/dev/null || fail "school search result is invalid"
pass "school search"

meal_status=$(request "$LIVE_ORIGIN" fetchMeals \
  '{"officeCode":"B10","schoolCode":"7010700","date":"20260601"}' "$TMP_DIR/meal.json")
[ "$meal_status" = 200 ] || fail "meal returned HTTP $meal_status"
jq -e '.ok == true and .data.date == "20260601" and (.data.menuItems | length > 0) and any(.data.menuItems[]; .allergyCodes | length > 0) and (.data.calorie != null) and (.data.nutrition != null)' \
  "$TMP_DIR/meal.json" >/dev/null || fail "meal response is incomplete"
pass "June 2026 meal with allergens, calories, and nutrition"
