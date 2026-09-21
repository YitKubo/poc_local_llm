#!/usr/bin/env bash
# Issue one LiteLLM virtual key per name, with the per-key limits from .env.
#   ./scripts/create_keys.sh alice bob carol
# Prints "<name> <key>" lines. Keys are shown once here; store them yourself.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 1 ] || { echo "usage: $0 <name> [<name> ...]" >&2; exit 1; }
[ -f .env ] || { echo "ERROR: .env not found" >&2; exit 1; }
set -a; . ./.env; set +a

URL="${LITELLM_URL:-http://127.0.0.1:4000}"
MODEL="${CLIENT_MODEL:-local-qwen}"

for name in "$@"; do
  body=$(NAME="$name" MODEL="$MODEL" python3 - <<'EOF'
import json, os
print(json.dumps({
    "key_alias": os.environ["NAME"],
    "models": [os.environ["MODEL"]],
    "max_parallel_requests": int(os.environ["MAX_PARALLEL_REQUESTS"]),
    "rpm_limit": int(os.environ["RPM_LIMIT"]),
    "tpm_limit": int(os.environ["TPM_LIMIT"]),
    "max_budget": float(os.environ["DAILY_BUDGET"]),
    "budget_duration": "1d",
}))
EOF
)
  resp=$(curl -sS -X POST "$URL/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" -d "$body")
  key=$(printf '%s' "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
  if [ -n "$key" ]; then
    echo "$name $key"
  else
    echo "ERROR creating '$name': $resp" >&2
    exit 1
  fi
done
