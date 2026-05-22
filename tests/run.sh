#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/tahr-trigger.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=""
data=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    -X|-H)
      shift 2
      ;;
    -sS)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s' "$data" > "$MOCK_CAPTURE/body.json"
printf '%s' "$url" > "$MOCK_CAPTURE/url.txt"
response="${MOCK_RESPONSE:-}"
if [[ -z "$response" ]]; then
  response='{"success":true,"assessmentId":"assessment_123","assessmentType":"source_code_analysis","status":"queued"}'
fi
if [[ -n "${MOCK_CURL_EXIT:-}" ]]; then
  echo "${MOCK_CURL_ERROR:-curl failed}" >&2
  exit "$MOCK_CURL_EXIT"
fi
printf '%s' "$response" > "$output"
printf '%s' "${MOCK_HTTP_CODE:-202}"
MOCK
chmod +x "$TMP_DIR/bin/curl"

run_success() {
  local output_file="$TMP_DIR/github-output-success"
  : > "$output_file"
  PATH="$TMP_DIR/bin:$PATH" \
  MOCK_CAPTURE="$TMP_DIR" \
  GITHUB_OUTPUT="$output_file" \
  TAHR_API_URL="https://run.app.tahr.one/" \
  TAHR_APPLICATION_ID="app_123" \
  TAHR_TRIGGER_TOKEN="secret-token" \
  TAHR_ASSESSMENT_TYPE="source_code_analysis" \
  TAHR_RESERVED_IP_ID="" \
  bash "$SCRIPT" >/tmp/tahr-action-success.log

  grep -q 'assessment-id=assessment_123' "$output_file"
  grep -q 'assessment-type=source_code_analysis' "$output_file"
  grep -q 'status=queued' "$output_file"
  grep -q 'https://run.app.tahr.one/integrations/applications/app_123/start' "$TMP_DIR/url.txt"
  grep -q '{"assessmentType":"source_code_analysis"}' "$TMP_DIR/body.json"
}

run_reserved_ip_success() {
  local output_file="$TMP_DIR/github-output-reserved"
  : > "$output_file"
  PATH="$TMP_DIR/bin:$PATH" \
  MOCK_CAPTURE="$TMP_DIR" \
  GITHUB_OUTPUT="$output_file" \
  TAHR_API_URL="https://run.app.tahr.one" \
  TAHR_APPLICATION_ID="app_123" \
  TAHR_TRIGGER_TOKEN="secret-token" \
  TAHR_ASSESSMENT_TYPE="full-no-authz" \
  TAHR_RESERVED_IP_ID="reserved_123" \
  bash "$SCRIPT" >/tmp/tahr-action-reserved.log

  grep -q '{"assessmentType":"full-no-authz","reservedIpId":"reserved_123"}' "$TMP_DIR/body.json"
}

run_failure() {
  local output_file="$TMP_DIR/github-output-failure"
  : > "$output_file"
  if PATH="$TMP_DIR/bin:$PATH" \
    MOCK_CAPTURE="$TMP_DIR" \
    MOCK_HTTP_CODE="401" \
    MOCK_RESPONSE='{"success":false,"error":"Unauthorized"}' \
    GITHUB_OUTPUT="$output_file" \
    TAHR_API_URL="https://run.app.tahr.one" \
    TAHR_APPLICATION_ID="app_123" \
    TAHR_TRIGGER_TOKEN="bad-token" \
    TAHR_ASSESSMENT_TYPE="full" \
    TAHR_RESERVED_IP_ID="" \
    bash "$SCRIPT" >/tmp/tahr-action-failure.log 2>&1; then
    echo "expected failure for 401 response" >&2
    exit 1
  fi
  grep -q 'HTTP 401: Unauthorized' /tmp/tahr-action-failure.log
}

run_message_failure() {
  local output_file="$TMP_DIR/github-output-message-failure"
  : > "$output_file"
  if PATH="$TMP_DIR/bin:$PATH" \
    MOCK_CAPTURE="$TMP_DIR" \
    MOCK_HTTP_CODE="403" \
    MOCK_RESPONSE='{"success":false,"message":"Assessment type is not allowed"}' \
    GITHUB_OUTPUT="$output_file" \
    TAHR_API_URL="https://run.app.tahr.one" \
    TAHR_APPLICATION_ID="app_123" \
    TAHR_TRIGGER_TOKEN="secret-token" \
    TAHR_ASSESSMENT_TYPE="full" \
    TAHR_RESERVED_IP_ID="" \
    bash "$SCRIPT" >/tmp/tahr-action-message-failure.log 2>&1; then
    echo "expected failure for message response" >&2
    exit 1
  fi
  grep -q 'HTTP 403: Assessment type is not allowed' /tmp/tahr-action-message-failure.log
}

run_network_failure() {
  local output_file="$TMP_DIR/github-output-network-failure"
  : > "$output_file"
  if PATH="$TMP_DIR/bin:$PATH" \
    MOCK_CAPTURE="$TMP_DIR" \
    MOCK_CURL_EXIT="6" \
    MOCK_CURL_ERROR="curl: (6) Could not resolve host: run.app.tahr.one" \
    GITHUB_OUTPUT="$output_file" \
    TAHR_API_URL="https://run.app.tahr.one" \
    TAHR_APPLICATION_ID="app_123" \
    TAHR_TRIGGER_TOKEN="secret-token" \
    TAHR_ASSESSMENT_TYPE="full" \
    TAHR_RESERVED_IP_ID="" \
    bash "$SCRIPT" >/tmp/tahr-action-network-failure.log 2>&1; then
    echo "expected failure for curl network error" >&2
    exit 1
  fi
  grep -q 'Tahr trigger request failed: curl: (6) Could not resolve host: run.app.tahr.one' /tmp/tahr-action-network-failure.log
}

run_success
run_reserved_ip_success
run_failure
run_message_failure
run_network_failure

echo "tests passed"
