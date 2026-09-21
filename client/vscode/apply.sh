#!/usr/bin/env bash
# Generate VS Code's chatLanguageModels.json from ./.env, so no tracked file ever holds the key.
# VS Code cannot read environment variables in that file, so this script bridges .env -> the file.
#
#   cp .env.example .env      # edit .env (gitignored): set LLM_SERVER_KEY
#   ./apply.sh                # add/replace the "poc_local_llm" group in VS Code's file
#   ./apply.sh --dry-run      # show the target and the result (key masked); write nothing
#   ./apply.sh --uninstall    # remove only the "poc_local_llm" group
#
# Other groups already in the file are kept. If the file had other groups, it is copied to
# <file>.bak first. The template is chatLanguageModels.sample.json (placeholders only).
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "ERROR: $*" >&2; exit 1; }

MODE=apply
case "${1:-}" in
  "") ;;
  --dry-run) MODE=dry;;
  --uninstall) MODE=uninstall;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "usage: $0 [--dry-run|--uninstall]" >&2; exit 1;;
esac

[ -f .env ] || die ".env not found. Run: cp .env.example .env   (then set LLM_SERVER_KEY)"
set -a; . ./.env; set +a

URL="${LLM_SERVER_URL:-}"
KEY="${LLM_SERVER_KEY:-}"
MODEL="${CLIENT_MODEL:-local-qwen}"
MAX_IN="${MAX_INPUT_TOKENS:-8000}"
MAX_OUT="${MAX_OUTPUT_TOKENS:-2048}"
PROFILE="${VSCODE_PROFILE:-}"
USER_DIR="${VSCODE_USER_DIR:-}"

if [ "$MODE" != uninstall ]; then
  [ -n "$URL" ] || die "LLM_SERVER_URL is empty in .env"
  case "$KEY" in ""|*REPLACE*) die "set LLM_SERVER_KEY in .env (still empty or the placeholder)";; esac
  case "$MAX_IN$MAX_OUT" in *[!0-9]*) die "MAX_INPUT_TOKENS / MAX_OUTPUT_TOKENS must be numbers";; esac
fi

# 1) VS Code's "User" directory
if [ -z "$USER_DIR" ]; then
  case "$(uname -s)" in
    Darwin) USER_DIR="$HOME/Library/Application Support/Code/User";;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then   # WSL: VS Code runs on the Windows side
        cands=()
        for d in /mnt/c/Users/*/AppData/Roaming/Code/User; do [ -d "$d" ] && cands+=("$d"); done
        [ "${#cands[@]}" -eq 1 ] || die "found ${#cands[@]} Windows VS Code user dirs; set VSCODE_USER_DIR in .env"
        USER_DIR="${cands[0]}"
      else
        USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
      fi;;
    *) die "unsupported OS; set VSCODE_USER_DIR in .env";;
  esac
fi
[ -d "$USER_DIR" ] || die "VS Code user dir not found: $USER_DIR (set VSCODE_USER_DIR in .env)"

# 2) the file for the chosen profile (each profile has its own chatLanguageModels.json)
if [ -n "$PROFILE" ]; then
  [ -f "$USER_DIR/globalStorage/storage.json" ] || die "$USER_DIR/globalStorage/storage.json not found"
  loc="$(PROFILE="$PROFILE" python3 - "$USER_DIR/globalStorage/storage.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for p in d.get("userDataProfiles") or []:
    if p.get("name") == os.environ["PROFILE"]:
        print(p["location"]); break
PY
)"
  [ -n "$loc" ] || die "profile '$PROFILE' not found. In VS Code run 'Profiles: Create Profile...' (Empty) first, or empty VSCODE_PROFILE for the Default profile"
  TARGET="$USER_DIR/profiles/$loc/chatLanguageModels.json"
  [ -d "$USER_DIR/profiles/$loc" ] || die "profile folder missing: $USER_DIR/profiles/$loc"
else
  TARGET="$USER_DIR/chatLanguageModels.json"
fi

# 3) build (from the template) / merge / write
MODE="$MODE" TARGET="$TARGET" URL="$URL" KEY="$KEY" MODEL="$MODEL" MAX_IN="$MAX_IN" MAX_OUT="$MAX_OUT" \
python3 - <<'PY'
import json, os, shutil, sys

GROUP = "poc_local_llm"
mode, target = os.environ["MODE"], os.environ["TARGET"]
key = os.environ["KEY"]
mask = lambda s: s.replace(key, key[:5] + "...(masked)") if key else s

cur = []
if os.path.exists(target) and os.path.getsize(target) > 0:
    try:
        cur = json.load(open(target, encoding="utf-8"))
    except ValueError as e:
        sys.exit(f"ERROR: {target} is not plain JSON ({e}). Comments are not supported; fix or move it first.")
if not isinstance(cur, list):
    sys.exit(f"ERROR: {target} is not a JSON array")
others = [g for g in cur if not (isinstance(g, dict) and g.get("name") == GROUP)]

if mode == "uninstall":
    new = others
else:
    tpl = json.load(open("chatLanguageModels.sample.json", encoding="utf-8"))
    group = next(g for g in tpl if g["name"] == GROUP)
    m = group["models"][0]
    base = os.environ["URL"].rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3]
    m["id"] = os.environ["MODEL"]
    m["name"] = f'{os.environ["MODEL"]} ({GROUP})'
    m["url"] = base + "/v1/chat/completions"
    m["maxInputTokens"] = int(os.environ["MAX_IN"])
    m["maxOutputTokens"] = int(os.environ["MAX_OUT"])
    m["requestHeaders"] = {"Authorization": "Bearer " + key}
    new = others + [group]

text = json.dumps(new, ensure_ascii=False, indent=2) + "\n"
print(("would write" if mode == "dry" else "target:"), target)
if mode == "dry":
    print(mask(text))
    sys.exit(0)
if others and os.path.exists(target):
    shutil.copy2(target, target + ".bak")
    print("backup:", target + ".bak")
open(target, "w", encoding="utf-8").write(text)
if mode == "uninstall":
    print(f"removed group '{GROUP}' ({len(others)} other group(s) kept)")
else:
    print(f"wrote group '{GROUP}': model {m['id']}, url {m['url']}, key {key[:5]}...(masked)")
PY
