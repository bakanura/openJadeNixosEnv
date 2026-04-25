#!/usr/bin/env bash
# HELP_CMD=clawbuddy
# HELP_FLAGS=[claw arguments...]
# HELP_DESC=Launch Claw Code Local against the local Ollama server with the default qwen2.5-coder profile in workspace-write mode.
# HELP_EXAMPLE=clawbuddy
set -euo pipefail

export OPENAI_API_KEY="ollama"
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
export OLLAMA_HOST="127.0.0.1:11434"

unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL
unset GOOGLE_API_KEY
unset OPENROUTER_API_KEY
unset DEEPSEEK_API_KEY
unset XAI_API_KEY
unset GROQ_API_KEY
unset MISTRAL_API_KEY

if [ "${PWD:-}" = "${HOME:-}" ]; then
  printf '%s\n' "clawbuddy is starting from \$HOME, so the current workspace is your whole home directory." >&2
  printf '%s\n' "Tip: cd into a repo or project first if you want narrower access." >&2
fi

if ! curl -s "http://${OLLAMA_HOST}/api/tags" >/dev/null; then
  printf '%s\n' "[ERROR] Ollama server not reachable at ${OLLAMA_HOST}. Is the service running?" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  exec claw --permission-mode workspace-write --model qwen2.5-coder:7b
fi

exec claw --permission-mode workspace-write --model qwen2.5-coder:7b "$@"
