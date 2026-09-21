#!/usr/bin/env bash
# Undo what install.sh set up for this server. Only touches what install.sh wrote.
#
#   ./uninstall.sh           remove the server registration, llm-agent, the stored key, and the default model
#   ./uninstall.sh --purge   also remove the `llm` CLI itself and its history (logs.db)
#
# --purge removes `llm` even if you had it before install.sh ran (install.sh cannot tell).
set -euo pipefail

PURGE=0
case "${1:-}" in
  --purge) PURGE=1;;
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  "") ;;
  *) echo "usage: $0 [--purge]" >&2; exit 1;;
esac

if command -v llm >/dev/null 2>&1; then
  cfg_dir="$(dirname "$(llm logs path)")"
else
  cfg_dir="${LLM_USER_PATH:-$HOME/.config/io.datasette.llm}"
fi

# 1) server registration (only if install.sh wrote it)
models_yaml="$cfg_dir/extra-openai-models.yaml"
if [ -f "$models_yaml" ] && grep -q 'api_key_name: local-llm' "$models_yaml"; then
  rm -f "$models_yaml"; echo "removed $models_yaml"
fi

# 1b) the shell tool and the llm-agent wrapper (only if install.sh wrote them)
if [ -f "$cfg_dir/agent_tools.py" ]; then
  rm -f "$cfg_dir/agent_tools.py"; echo "removed $cfg_dir/agent_tools.py"
fi
agent="$HOME/.local/bin/llm-agent"
if [ -f "$agent" ] && grep -q 'Written by install.sh' "$agent"; then
  rm -f "$agent"; echo "removed $agent"
fi

# 2) stored virtual key; other keys in keys.json are left alone
keys_json="$cfg_dir/keys.json"
if [ -f "$keys_json" ]; then
  KEYS_JSON="$keys_json" python3 - <<'EOF'
import json, os
p = os.environ["KEYS_JSON"]
keys = json.load(open(p))
if "local-llm" in keys:
    del keys["local-llm"]
    if keys:
        json.dump(keys, open(p, "w"), indent=2)
        print(f"removed key 'local-llm' from {p}")
    else:
        os.remove(p)
        print(f"removed {p}")
EOF
fi

# 3) default model, only if it is the one install.sh set
default_txt="$cfg_dir/default_model.txt"
if [ -f "$default_txt" ] && [ "$(tr -d '[:space:]' < "$default_txt")" = "local" ]; then
  rm -f "$default_txt"; echo "removed $default_txt"
fi

if [ "$PURGE" = 1 ]; then
  # 4) history
  if [ -f "$cfg_dir/logs.db" ]; then rm -f "$cfg_dir/logs.db"; echo "removed $cfg_dir/logs.db"; fi
  rmdir "$cfg_dir" 2>/dev/null && echo "removed $cfg_dir" || true

  # 5) the llm CLI: pipx install, or the private venv install.sh creates
  if command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^llm '; then
    pipx uninstall llm
  fi
  venv="$HOME/.local/share/llm-venv"
  link="$HOME/.local/bin/llm"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$venv/bin/llm" ]; then
    rm -f "$link"; echo "removed $link"
  fi
  if [ -d "$venv" ]; then rm -rf "$venv"; echo "removed $venv"; fi
fi

echo "done."
[ "$PURGE" = 1 ] || echo "(llm itself and its history are kept; use --purge to remove them)"
