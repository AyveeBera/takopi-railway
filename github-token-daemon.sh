#!/bin/bash
set -euo pipefail

token_file="${GITHUB_TOKEN_FILE:-/run/github-token}"
expires_file="${GITHUB_TOKEN_EXPIRES_FILE:-${token_file}.expires_at}"

retry_s="${GITHUB_TOKEN_RETRY_SECONDS:-60}"
min_sleep_s="${GITHUB_TOKEN_MIN_SLEEP_SECONDS:-60}"
max_sleep_s="${GITHUB_TOKEN_MAX_SLEEP_SECONDS:-3300}"
safety_s="${GITHUB_TOKEN_REFRESH_SAFETY_SECONDS:-300}"

fixed_interval_s="${GITHUB_TOKEN_REFRESH_SECONDS:-}"
fallback_interval_s="${GITHUB_TOKEN_FALLBACK_REFRESH_SECONDS:-3000}"

calc_sleep_from_expiry() {
  local expires_at expiry_epoch now delta
  [[ -f "$expires_file" ]] || return 1
  expires_at="$(cat "$expires_file" 2>/dev/null || true)"
  [[ -n "$expires_at" ]] || return 1

  expiry_epoch="$(date -d "$expires_at" +%s 2>/dev/null || true)"
  [[ -n "$expiry_epoch" ]] || return 1

  now="$(date +%s)"
  delta="$((expiry_epoch - now - safety_s))"
  if (( delta < min_sleep_s )); then
    delta="$min_sleep_s"
  elif (( delta > max_sleep_s )); then
    delta="$max_sleep_s"
  fi

  printf '%s' "$delta"
}

while true; do
  if ! /usr/local/bin/refresh-github-token.sh; then
    echo "⚠ GitHub App token refresh failed; will retry in ${retry_s}s" >&2
    sleep "$retry_s" || exit 0
    continue
  fi

  if [[ -n "$fixed_interval_s" ]]; then
    sleep "$fixed_interval_s" || exit 0
    continue
  fi

  if next_sleep="$(calc_sleep_from_expiry)"; then
    sleep "$next_sleep" || exit 0
    continue
  fi

  sleep "$fallback_interval_s" || exit 0
done
