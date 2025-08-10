#!/usr/bin/env bash
# check_backend.sh — CrimeSenseAI backend pre-FE smoke test
# Usage: BASE="http://api.crimeai.local" ./check_backend.sh

set -euo pipefail

BASE="${BASE:-http://api.crimeai.local}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Required command '$1' not found"; exit 1; }; }
need_cmd curl
need_cmd jq

echo "🔗 BASE=${BASE}"

# 1) /sync must be POST and succeed
echo "▶ Check /sync method"
ALLOW=$(curl -isS -X OPTIONS "$BASE/sync" | tr -d '\r' | awk '/^Allow:/ {print $2}')
if [[ "${ALLOW,,}" != "post" ]]; then
  echo "❌ /sync Allow method is '$ALLOW' (expected POST)"
  exit 1
fi
echo "✅ /sync Allow: POST"

echo "▶ Run /sync (POST)"
SYNC_JSON=$(curl -fsS -X POST "$BASE/sync")
echo "$SYNC_JSON" | jq . >/dev/null || { echo "❌ /sync returned non-JSON"; exit 1; }
echo "✅ /sync POST OK"
# Optional: surface quick summary
UPSERT=$(echo "$SYNC_JSON" | jq -r '.upserted_cases // .updated_cases // empty')
EVID=$(echo "$SYNC_JSON" | jq -r '.inserted_evidences // .evidences // empty')
[[ -n "${UPSERT}" ]] && echo "   ↳ upserted_cases: ${UPSERT}"
[[ -n "${EVID}"   ]] && echo "   ↳ evidences: ${EVID}"

# 2) /openapi.json reachable
echo "▶ Check openapi.json"
OPENAPI=$(curl -fsS "$BASE/openapi.json")
echo "$OPENAPI" | jq '.info.title,.info.version' >/dev/null
echo "✅ openapi.json OK"

# 3) Required endpoints present
echo "▶ Verify required paths exist in openapi"
required_paths=("/sync" "/stats")
for p in "${required_paths[@]}"; do
  echo "$OPENAPI" | jq -e --arg p "$p" '.paths[$p]' >/dev/null \
    && echo "   ✅ found $p" \
    || { echo "   ❌ missing $p"; exit 1; }
done

# 4) Discover cases endpoint automatically
echo "▶ Discover cases endpoint"
CASES_PATH=""
# Prefer /cases/v2 if present
if echo "$OPENAPI" | jq -e '.paths["/cases/v2"]' >/dev/null 2>&1; then
  CASES_PATH="/cases/v2"
else
  # Fallback: any path containing "cases" that supports GET
  CASES_PATH=$(echo "$OPENAPI" \
    | jq -r '.paths | to_entries[] | select(.key|test("cases")) | select(.value.get!=null) | .key' \
    | head -n1)
fi

if [[ -z "$CASES_PATH" ]]; then
  echo "   ❌ No GET-able cases endpoint found in openapi (expected /cases or /cases/v2)"
  exit 1
fi
echo "   ✅ using cases endpoint: $CASES_PATH"

# 5) Test /stats
echo "▶ /stats"
STAT_JSON=$(curl -fsS "$BASE/stats")
echo "$STAT_JSON" | jq . >/dev/null || { echo "❌ /stats returned non-JSON"; exit 1; }
echo "✅ /stats OK"
# Optional quick check
CASES_COUNT=$(echo "$STAT_JSON" | jq -r '.cases // empty')
EVID_COUNT=$(echo "$STAT_JSON" | jq -r '.evidences // empty')
if [[ -n "$CASES_COUNT" && -n "$EVID_COUNT" ]]; then
  echo "   ↳ cases: ${CASES_COUNT}, evidences: ${EVID_COUNT}"
fi

# 6) Test cases endpoint
echo "▶ $CASES_PATH"
curl -fsS "$BASE$CASES_PATH" | head -c 500 >/dev/null
echo "✅ $CASES_PATH OK"

echo "🎉 Smoke test passed — ready for Frontend"

