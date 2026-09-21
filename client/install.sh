#!/usr/bin/env bash
# Set up the `llm` CLI (https://llm.datasette.io) on a client machine.
# Self-contained: needs only the server URL and your virtual key. Nothing in server/ is used.
#
#   ./install.sh http://<server-host>:4000 sk-<your-virtual-key>
# or with env:
#   LLM_SERVER_URL=... LLM_SERVER_KEY=... ./install.sh
#
# Optional env:
#   CLIENT_MODEL   model name published by the server (default: local-qwen)
#
# Then:  llm "hello"    llm chat
set -euo pipefail

usage() { echo "usage: $0 <server-url e.g. http://host:4000> <virtual-key>" >&2; }
case "${1:-}" in -h|--help) usage; exit 0;; esac

URL="${1:-${LLM_SERVER_URL:-}}"
KEY="${2:-${LLM_SERVER_KEY:-}}"
MODEL_NAME="${CLIENT_MODEL:-local-qwen}"
[ -n "$URL" ] && [ -n "$KEY" ] || { usage; exit 1; }
URL="${URL%/}"

# 1) install `llm`: pipx if present, otherwise a private venv linked into ~/.local/bin
if ! command -v llm >/dev/null 2>&1; then
  if command -v pipx >/dev/null 2>&1; then
    pipx install llm
  else
    echo "pipx not found; using a private venv at ~/.local/share/llm-venv"
    python3 -m venv ~/.local/share/llm-venv
    ~/.local/share/llm-venv/bin/pip install -q llm
    mkdir -p ~/.local/bin
    ln -sf ~/.local/share/llm-venv/bin/llm ~/.local/bin/llm
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "NOTE: add ~/.local/bin to PATH";; esac
  fi
fi
LLM="$(command -v llm || echo "$HOME/.local/bin/llm")"

# 2) register the server as a model
cfg_dir="$(dirname "$("$LLM" logs path)")"
mkdir -p "$cfg_dir"
cat > "$cfg_dir/extra-openai-models.yaml" <<EOF
- model_id: local
  model_name: ${MODEL_NAME}
  api_base: "${URL}/v1"
  api_key_name: local-llm
EOF

# 3) store this user's virtual key, 4) make the model the default
"$LLM" keys set local-llm --value "$KEY"
"$LLM" models default local

echo "ok. try:  llm \"hello\"   or   llm chat"
echo "config: $cfg_dir/extra-openai-models.yaml"
