#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://api.crimeai.local}"
JQ="${JQ:-jq}"

say() { echo -e "\n\033[1;36m== $* ==\033[0m"; }
fail() { echo -e "\033[1;31m$*\033[0m" >&2; exit 1; }

check_cmds() {
  command -v curl >/dev/null || fail "curl not found"
  command -v $JQ   >/dev/null || fail "$JQ not found (install jq or set JQ=python)"
}

# pretty print with jq, else show raw
pp() {
  local body="$1"
  echo "$body" | $JQ . >/dev/null 2>&1 && echo "$body" | $JQ . || {
    echo "---- raw response (not JSON) ----"
    echo "$body"
  }
}

pick_case_id() {
  if [[ -n "${CASE_ID:-}" ]]; then
    echo "$CASE_ID"; return 0
  fi
  local cid
  cid="$(curl -sS "$BASE/cases?limit=1" -H 'Accept: application/json' | jq -r '.[0].case_id // empty' || true)"
  [[ -n "$cid" && "$cid" != "null" ]] && { echo "$cid"; return 0; }
  cid="$(curl -sS "$BASE/cases/v2?limit=1" -H 'Accept: application/json' | jq -r '.items[0].case_id // empty' || true)"
  [[ -n "$cid" && "$cid" != "null" ]] && { echo "$cid"; return 0; }
  return 1
}

main() {
  check_cmds

  say "OpenAPI paths"
  pp "$(curl -sS "$BASE/openapi.json")"

  say "GET /health"
  pp "$(curl -sS "$BASE/health")"

  say "GET /version"
  pp "$(curl -sS "$BASE/version")"

  say "GET /cases (v1 sample)"
  pp "$(curl -sS "$BASE/cases?limit=5" -H 'Accept: application/json')"

  say "GET /cases/v2 (paged sample)"
  pp "$(curl -sS "$BASE/cases/v2?limit=5" -H 'Accept: application/json')"

  say "Filter + order (/cases/v2)"
  pp "$(curl -sS "$BASE/cases/v2?center_code=01-SRI&order_by=incident_time:desc&limit=5" -H 'Accept: application/json')"

  say "Search q (/cases/v2)"
  # ใช้ --data-urlencode เพื่อกันปัญหาอักษรไทย/ช่องว่าง และใส่ Accept header ด้วย
  RESP="$(curl -sS -G "$BASE/cases/v2" \
    --data-urlencode "q=${Q:-แก่งคอย}" \
    --data-urlencode "limit=5" \
    -H 'Accept: application/json')"
  pp "$RESP"

  say "Date range (/cases/v2)"
  pp "$(curl -sS "$BASE/cases/v2?date_from=2025-07-01&date_to=2025-07-31&limit=5" -H 'Accept: application/json')"

  say "Select fields (/cases/v2)"
  pp "$(curl -sS "$BASE/cases/v2?fields=case_id,CenterCode,SceneDescription,incident_time&limit=3" -H 'Accept: application/json')"

  say "Centers summary (/cases/centers)"
  pp "$(curl -sS "$BASE/cases/centers" -H 'Accept: application/json')"

  say "Case detail (/cases/{case_id})"
  CID="$(pick_case_id || true)"
  if [[ -z "${CID:-}" ]]; then
    echo "No case_id found automatically. Set CASE_ID=<id> and rerun." >&2
  else
    echo "Using case_id: $CID"
    pp "$(curl -sS "$BASE/cases/$CID" -H 'Accept: application/json')"
  fi

  say "Admin explain (/admin/explain; requires ENABLE_DEV=1)"
  if curl -sS "$BASE/openapi.json" | jq -e '.paths["/admin/explain"]' >/dev/null; then
    pp "$(curl -sS -X POST "$BASE/admin/explain" -H 'Content-Type: application/json' \
      -d '{"sql":"SELECT COUNT(*) FROM cases"}')"
  else
    echo "No /admin/explain in OpenAPI (skipping)."
  fi

  say "DONE"
}

main "$@"
