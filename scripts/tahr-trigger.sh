#!/usr/bin/env bash
set -euo pipefail

fail() {
  local message="$1"
  echo "::error::$message" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "$name is required"
  fi
}

validate_simple_value() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    fail "$name contains unsupported characters"
  fi
}

json_field() {
  local file="$1"
  local field="$2"
  node -e '
const fs = require("fs");
const file = process.argv[1];
const field = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
const value = data[field];
if (value !== undefined && value !== null) process.stdout.write(String(value));
' "$file" "$field"
}

single_line() {
  tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g' | cut -c 1-300
}

require_env TAHR_API_URL
require_env TAHR_APPLICATION_ID
require_env TAHR_TRIGGER_TOKEN
require_env TAHR_ASSESSMENT_TYPE

validate_simple_value TAHR_APPLICATION_ID "$TAHR_APPLICATION_ID"
validate_simple_value TAHR_ASSESSMENT_TYPE "$TAHR_ASSESSMENT_TYPE"
if [[ -n "${TAHR_RESERVED_IP_ID:-}" ]]; then
  validate_simple_value TAHR_RESERVED_IP_ID "$TAHR_RESERVED_IP_ID"
fi

if ! command -v node >/dev/null 2>&1; then
  fail "node is required to parse Tahr API responses"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required to call Tahr"
fi

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::add-mask::$TAHR_TRIGGER_TOKEN"
fi

base_url="${TAHR_API_URL%/}"
endpoint="$base_url/integrations/applications/$TAHR_APPLICATION_ID/start"

body="{\"assessmentType\":\"$TAHR_ASSESSMENT_TYPE\"}"
if [[ -n "${TAHR_RESERVED_IP_ID:-}" ]]; then
  body="{\"assessmentType\":\"$TAHR_ASSESSMENT_TYPE\",\"reservedIpId\":\"$TAHR_RESERVED_IP_ID\"}"
fi

response_file="$(mktemp)"
curl_error_file="$(mktemp)"
trap 'rm -f "$response_file" "$curl_error_file"' EXIT

if ! http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$endpoint" \
  -H "X-Trigger-Token: $TAHR_TRIGGER_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$body" 2>"$curl_error_file")"; then
  curl_error="$(single_line < "$curl_error_file")"
  fail "Tahr trigger request failed${curl_error:+: $curl_error}"
fi

if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
  fail "Tahr trigger returned invalid HTTP status: $http_code"
fi

if [[ "$http_code" != 2* ]]; then
  error_message="$(json_field "$response_file" error 2>/dev/null || true)"
  if [[ -z "$error_message" ]]; then
    error_message="$(json_field "$response_file" message 2>/dev/null || true)"
  fi
  if [[ -z "$error_message" ]]; then
    error_message="$(json_field "$response_file" detail 2>/dev/null || true)"
  fi
  if [[ -z "$error_message" ]]; then
    error_message="$(single_line < "$response_file")"
  fi
  fail "Tahr trigger failed with HTTP $http_code${error_message:+: $error_message}"
fi

success="$(json_field "$response_file" success 2>/dev/null || true)"
if [[ "$success" != "true" ]]; then
  fail "Tahr trigger response did not include success=true"
fi

assessment_id="$(json_field "$response_file" assessmentId 2>/dev/null || true)"
assessment_type="$(json_field "$response_file" assessmentType 2>/dev/null || true)"
status="$(json_field "$response_file" status 2>/dev/null || true)"

if [[ -z "$assessment_id" ]]; then
  fail "Tahr trigger response did not include assessmentId"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "assessment-id=$assessment_id"
    echo "assessment-type=$assessment_type"
    echo "status=$status"
  } >> "$GITHUB_OUTPUT"
fi

echo "Tahr assessment queued: $assessment_id"
