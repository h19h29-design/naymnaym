#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="${ASC_BUNDLE_ID:-com.h19h29.naymnaymlevelup}"
VERSION="${ASC_VERSION:-1.0}"
BUILD_NUMBER="${ASC_BUILD:-15}"
KEY_ID="${ASC_KEY_ID:-}"
ISSUER_ID="${ASC_ISSUER_ID:-}"
PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-}"
REQUIRE_BETA_GROUPS="${ASC_REQUIRE_BETA_GROUPS:-0}"
EXPECTED_BETA_GROUP_NAME="${ASC_EXPECTED_BETA_GROUP_NAME:-}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -n "$KEY_ID" ] || fail "ASC_KEY_ID is required"
[ -n "$ISSUER_ID" ] || fail "ASC_ISSUER_ID is required"
[ -n "$PRIVATE_KEY_PATH" ] || fail "ASC_PRIVATE_KEY_PATH is required"
[ -f "$PRIVATE_KEY_PATH" ] || fail "ASC_PRIVATE_KEY_PATH does not point to a file"
case "$REQUIRE_BETA_GROUPS" in
  0|1) ;;
  *) fail "ASC_REQUIRE_BETA_GROUPS must be 0 or 1" ;;
esac

ruby - "$KEY_ID" "$ISSUER_ID" "$PRIVATE_KEY_PATH" "$BUNDLE_ID" "$VERSION" "$BUILD_NUMBER" "$REQUIRE_BETA_GROUPS" "$EXPECTED_BETA_GROUP_NAME" <<'RUBY'
require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

key_id, issuer_id, private_key_path, bundle_id, version, build_number, require_beta_groups, expected_beta_group_name = ARGV
require_beta_groups = require_beta_groups == "1"
expected_beta_group_name = expected_beta_group_name.to_s.strip
expect_beta_group = expected_beta_group_name != ""

def fail(message)
  warn "FAIL: #{message}"
  exit 1
end

def pass(message)
  puts "PASS: #{message}"
end

def info(message)
  puts "INFO: #{message}"
end

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

header = {
  alg: "ES256",
  kid: key_id,
  typ: "JWT"
}
payload = {
  iss: issuer_id,
  exp: Time.now.to_i + 20 * 60,
  aud: "appstoreconnect-v1"
}

private_key = OpenSSL::PKey.read(File.read(private_key_path))
segments = [
  base64url(JSON.generate(header)),
  base64url(JSON.generate(payload))
]
signing_input = segments.join(".")
signature = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
jwt = "#{signing_input}.#{base64url(signature)}"

def get_json(path, jwt, required: true)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{jwt}"
  request["Accept"] = "application/json"

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    prefix = required ? "FAIL" : "INFO"
    warn "#{prefix}: App Store Connect API returned HTTP #{response.code} for #{path}"
    warn response.body.to_s[0, 1000]
    exit 1 if required
    return nil
  end

  JSON.parse(response.body)
end

apps_query = URI.encode_www_form(
  "filter[bundleId]" => bundle_id,
  "limit" => "1"
)
apps = get_json("/v1/apps?#{apps_query}", jwt)
app = apps.fetch("data", []).first
fail "No App Store Connect app found for bundle id #{bundle_id}" unless app

app_id = app.fetch("id")
app_name = app.dig("attributes", "name") || bundle_id
info "app: #{app_name} (#{bundle_id})"

builds_query = URI.encode_www_form(
  "filter[app]" => app_id,
  "filter[version]" => version,
  "filter[buildNumber]" => build_number,
  "sort" => "-uploadedDate",
  "limit" => "1"
)
builds = get_json("/v1/builds?#{builds_query}", jwt)
build = builds.fetch("data", []).first
fail "No build found for #{version} (#{build_number})" unless build

attributes = build.fetch("attributes", {})
state = attributes["processingState"] || "unknown"
uploaded_date = attributes["uploadedDate"] || "unknown"
expiration_date = attributes["expirationDate"] || "unknown"
uses_non_exempt_encryption = attributes.key?("usesNonExemptEncryption") ? attributes["usesNonExemptEncryption"] : "unknown"

pass "found App Store Connect build #{version} (#{build_number})"
info "build id: #{build.fetch("id")}"
info "processing state: #{state}"
info "uploaded date: #{uploaded_date}"
info "expiration date: #{expiration_date}"
info "uses non-exempt encryption: #{uses_non_exempt_encryption}"

if state.to_s.upcase.match?(/FAIL|INVALID|REJECT/)
  fail "build processing state is #{state}"
end

if state.to_s.upcase == "PROCESSING"
  info "build is still processing; wait before connecting it to TestFlight groups"
else
  pass "build processing state is not an obvious failure"
end

beta_groups = get_json("/v1/builds/#{URI.encode_www_form_component(build.fetch("id"))}/betaGroups?limit=50", jwt, required: false)
if beta_groups
  groups = beta_groups.fetch("data", [])
  if groups.empty?
    message = "build #{version} (#{build_number}) is not attached to any TestFlight beta group"
    require_beta_groups || expect_beta_group ? fail(message) : info(message)
  else
    pass "build is attached to #{groups.length} TestFlight beta group(s)"
    group_names = groups.map { |group| group.dig("attributes", "name").to_s }
    groups.each do |group|
      attributes = group.fetch("attributes", {})
      name = attributes["name"] || group.fetch("id")
      group_type = attributes["isInternalGroup"] == true ? "internal" : "external"
      public_link_enabled = attributes.key?("publicLinkEnabled") ? attributes["publicLinkEnabled"] : "unknown"
      info "beta group: #{name} (#{group_type}, publicLinkEnabled=#{public_link_enabled})"
    end

    if expect_beta_group
      if group_names.include?(expected_beta_group_name)
        pass "expected TestFlight beta group is attached: #{expected_beta_group_name}"
      else
        fail "expected TestFlight beta group is not attached: #{expected_beta_group_name}"
      end
    end
  end
else
  message = "TestFlight beta group linkage check could not be completed because the betaGroups relationship endpoint was unavailable"
  require_beta_groups || expect_beta_group ? fail(message) : info(message)
end
RUBY
