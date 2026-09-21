#!/usr/bin/env bash
# Download the GGUF model into ./models (resumable). Reads MODEL_FILE / MODEL_URL from .env.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERROR: .env not found. Run: cp .env.example .env" >&2; exit 1; }
set -a; . ./.env; set +a

mkdir -p models
dest="models/${MODEL_FILE}"
if [ -s "$dest" ]; then
  echo "already present: $dest ($(du -h "$dest" | cut -f1))"
  exit 0
fi

echo "downloading ${MODEL_URL}"
quiet=(); [ -t 2 ] || quiet=(-sS)   # no progress meter when not on a terminal
curl -fL "${quiet[@]}" --retry 3 -C - -o "${dest}.part" "${MODEL_URL}"
mv "${dest}.part" "$dest"
echo "done: $dest ($(du -h "$dest" | cut -f1))"
