#!/usr/bin/env bash
# Issue one LiteLLM virtual key per name, with the per-key limits from .env.
#   ./scripts/create_keys.sh alice bob carol
#   ./scripts/create_keys.sh --rotate alice   # delete alice's existing key first, then reissue
# Prints "<name> <key>" lines. Keys are shown once here; store them yourself.
# An alias that already exists is an error unless --rotate is given (the old key stops working).
set -euo pipefail
cd "$(dirname "$0")/.."

ROTATE=0
if [ "${1:-}" = "--rotate" ]; then ROTATE=1; shift; fi
[ $# -ge 1 ] || { echo "usage: $0 [--rotate] <name> [<name> ...]" >&2; exit 1; }
[ -f .env ] || { echo "ERROR: .env not found" >&2; exit 1; }
set -a; . ./.env; set +a

URL="${LITELLM_URL:-http://127.0.0.1:4000}"
MODEL="${GATEWAY_MODEL:-local-qwen}"   # model_name in litellm_config.yaml

for name in "$@"; do
  if [ "$ROTATE" = 1 ]; then
    # Deleting a missing alias is harmless, so ignore the response.
    curl -sS -X POST "$URL/key/delete" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$(NAME="$name" python3 -c 'import json,os; print(json.dumps({"key_aliases":[os.environ["NAME"]]}))')" >/dev/null
  fi
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
    case "$resp" in
      *"already exists"*) echo "hint: '$name' was issued before. Reissue with: $0 --rotate $name  (the old key stops working)" >&2;;
    esac
    exit 1
  fi
done
