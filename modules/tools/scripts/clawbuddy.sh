#!/usr/bin/env bash
# HELP_CMD=clawbuddy
# HELP_FLAGS=[claw arguments...]
# HELP_DESC=Launch Claw Code Local against the local Ollama server with the default qwen2.5-coder profile.
# HELP_EXAMPLE=clawbuddy
set -euo pipefail

export OPENAI_API_KEY="ollama"
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"

unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL
unset GOOGLE_API_KEY
unset OPENROUTER_API_KEY
unset DEEPSEEK_API_KEY
unset XAI_API_KEY
unset GROQ_API_KEY
unset MISTRAL_API_KEY

if [ "$#" -eq 0 ]; then
  exec claw --model qwen2.5-coder:7b
fi

exec claw --model qwen2.5-coder:7b "$@"
