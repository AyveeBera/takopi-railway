#!/bin/bash
set -euo pipefail

token_file="${GITHUB_TOKEN_FILE:-/run/github-token}"
expires_file="${GITHUB_TOKEN_EXPIRES_FILE:-${token_file}.expires_at}"

api_url="${GITHUB_API_URL:-https://api.github.com}"
host="${GITHUB_HOST:-github.com}"

app_id="${GITHUB_APP_ID:-}"
installation_id="${GITHUB_APP_INSTALLATION_ID:-}"
private_key="${GITHUB_APP_PRIVATE_KEY:-}"
private_key_b64="${GITHUB_APP_PRIVATE_KEY_B64:-}"
private_key_file="${GITHUB_APP_PRIVATE_KEY_FILE:-}"

api_url="${api_url%/}"

curl_connect_timeout_s="${GITHUB_CURL_CONNECT_TIMEOUT_SECONDS:-5}"
curl_max_time_s="${GITHUB_CURL_MAX_TIME_SECONDS:-20}"

if [[ -n "$private_key_file" && -z "$private_key" ]]; then
  private_key="$(cat "$private_key_file")"
fi

strip_outer_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  fi
  if [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi
  printf '%s' "$value"
}

# Railway and similar UIs sometimes store values with surrounding quotes.
private_key="$(strip_outer_quotes "$private_key")"
private_key_b64="$(strip_outer_quotes "$private_key_b64")"

if [[ -z "$private_key_file" && -n "$private_key_b64" ]]; then
  set +e
  decoded="$(printf '%s' "$private_key_b64" | tr -d ' \n\t\r' | base64 -d 2>/dev/null)"
  rc="$?"
  if (( rc != 0 )); then
    decoded="$(printf '%s' "$private_key_b64" | tr -d ' \n\t\r' | base64 -D 2>/dev/null)"
    rc="$?"
  fi
  set -e

  if (( rc != 0 )); then
    echo "Could not decode GITHUB_APP_PRIVATE_KEY_B64 (base64 decode failed)" >&2
    exit 1
  fi
  private_key="$decoded"
fi

# Normalize CRLF -> LF.
private_key="${private_key//$'\r'/}"

if [[ -z "$app_id" || -z "$installation_id" || -z "$private_key" ]]; then
  exit 0
fi

umask 077

work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

key_file="$work_dir/github-app-private-key.pem"

# Support both \n and \\n encodings (some UIs double-escape backslashes).
private_key="${private_key//\\\\n/$'\n'}"
private_key="${private_key//\\n/$'\n'}"

printf '%s' "$private_key" > "$key_file"

if ! openssl pkey -in "$key_file" -noout >/dev/null 2>&1; then
  first_line="$(head -n 1 "$key_file" 2>/dev/null || true)"
  echo "Could not read GitHub App private key (first line: ${first_line})" >&2
  exit 1
fi

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
iat="$((now - 60))"
exp="$((now + 600))"

header_b64="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload_b64="$(printf '%s' "{\"iat\":$iat,\"exp\":$exp,\"iss\":$app_id}" | b64url)"
unsigned="${header_b64}.${payload_b64}"

sig_b64="$(printf '%s' "$unsigned" | openssl dgst -sha256 -binary -sign "$key_file" | b64url)"
jwt="${unsigned}.${sig_b64}"

body_file="$work_dir/resp.json"
set +e
http_code="$(
  curl -sS -o "$body_file" -w "%{http_code}" -X POST \
    --connect-timeout "$curl_connect_timeout_s" \
    --max-time "$curl_max_time_s" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${jwt}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_url}/app/installations/${installation_id}/access_tokens"
)"
curl_rc="$?"
set -e

if (( curl_rc != 0 )); then
  echo "GitHub App token request failed: curl exited with ${curl_rc} (connect_timeout=${curl_connect_timeout_s}s max_time=${curl_max_time_s}s)" >&2
  exit 1
fi

if [[ "$http_code" != "201" && "$http_code" != "200" ]]; then
  err_msg="$(
    python - <<'PY' <"$body_file" || true
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("unexpected non-JSON response")
    raise SystemExit(0)
msg = data.get("message") or "request failed"
doc = data.get("documentation_url") or ""
print(f"{msg}{' ('+doc+')' if doc else ''}")
PY
  )"
  echo "GitHub App token request failed (HTTP $http_code): ${err_msg:-request failed}" >&2
  exit 1
fi

mapfile -t parsed < <(
  python - <<'PY' <"$body_file"
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    data = {}
token = data.get("token", "")
expires_at = data.get("expires_at", "")
if not token:
    message = data.get("message", "missing token in response")
    raise SystemExit(message)
print(token)
print(expires_at)
PY
)

token="${parsed[0]:-}"
expires_at="${parsed[1]:-}"

tmp_token="$(mktemp "${token_file}.tmp.XXXXXX")"
chmod 0400 "$tmp_token"
printf '%s' "$token" > "$tmp_token"
mv -f "$tmp_token" "$token_file"

if [[ -n "$expires_at" ]]; then
  tmp_exp="$(mktemp "${expires_file}.tmp.XXXXXX")"
  chmod 0400 "$tmp_exp"
  printf '%s\n' "$expires_at" > "$tmp_exp"
  mv -f "$tmp_exp" "$expires_file"
fi

if command -v gh >/dev/null 2>&1; then
  if echo "$token" | gh auth login --hostname "$host" --with-token >/dev/null 2>&1; then
    if [[ ! -f /run/.gh-setup-git-done ]]; then
      gh auth setup-git --hostname "$host" >/dev/null 2>&1 || true
      : > /run/.gh-setup-git-done
    fi
  fi
fi
