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
#        llm-agent "run uname -r"          the model runs shell commands; asks y/N before each (default)
#        llm-agent --auto "run uname -r"   same, but runs them without asking
#        llm-agent                         same, as an interactive chat (add --auto to skip asking)
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

# 2) register the server as a model (supports_tools lets `llm --functions` use tool calling)
cfg_dir="$(dirname "$("$LLM" logs path)")"
mkdir -p "$cfg_dir"
cat > "$cfg_dir/extra-openai-models.yaml" <<EOF
- model_id: local
  model_name: ${MODEL_NAME}
  api_base: "${URL}/v1"
  api_key_name: local-llm
  supports_tools: true
EOF

# 3) tool calling: a shell tool, and `llm-agent` to run it in "ask" or "auto" mode
cat > "$cfg_dir/agent_tools.py" <<'PYEOF'
import subprocess


def run_shell(command: str) -> str:
    "Run a shell command and return its exit code and output."
    try:
        r = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return "error: command timed out after 60s"
    return f"exit code: {r.returncode}\n{(r.stdout + r.stderr)[-4000:]}"
PYEOF

mkdir -p ~/.local/bin
cat > ~/.local/bin/llm-agent <<'SHEOF'
#!/usr/bin/env bash
# llm-agent: let the model run shell commands (llm tool calling). Written by install.sh.
#   llm-agent [--ask|--auto] "<prompt>"   one shot: answer the prompt and exit
#   llm-agent [--ask|--auto]              interactive chat (type "exit" or Ctrl-D to quit)
#   --ask   (default) show each command and ask y/N before running it
#   --auto  run every command the model asks for, without asking
set -euo pipefail
mode=ask
case "${1:-}" in
  --ask) shift;;
  --auto) mode=auto; shift;;
  -h|--help) sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac
cmd=(llm)
if [ $# -eq 0 ]; then
  [ -t 0 ] || { echo "llm-agent: chat needs a terminal; give a prompt for one-shot use" >&2; exit 1; }
  cmd+=(chat)
elif [ "$mode" = ask ] && [ ! -t 0 ]; then
  echo "llm-agent: --ask needs a terminal on stdin to ask you (use --auto to run unattended)" >&2
  exit 1
fi
# a small model sometimes answers "I cannot run commands" unless told it has the tool
system="You can run shell commands on the user's computer with the run_shell tool. When the user asks you to run a command or check something on the computer, call run_shell instead of saying you cannot. After the tool result arrives, answer from that result."
args=(-s "$system" --functions "$(dirname "$(llm logs path)")/agent_tools.py" --td)
[ "$mode" = ask ] && args+=(--ta)
echo "llm-agent: mode=$mode" >&2
exec "${cmd[@]}" "${args[@]}" "$@"
SHEOF
chmod +x ~/.local/bin/llm-agent

# 4) store this user's virtual key, 5) make the model the default
"$LLM" keys set local-llm --value "$KEY"
"$LLM" models default local

echo "ok. try:  llm \"hello\"   llm chat   llm-agent \"run uname -r\""
echo "config: $cfg_dir/extra-openai-models.yaml"
