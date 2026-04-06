#!/usr/bin/env bash
# HELP_CMD=lamabuddy
# HELP_FLAGS=[aider arguments...]
# HELP_DESC=Launch aider against the local Ollama server with the default qwen2.5-coder profile.
# HELP_EXAMPLE=lamabuddy
set -euo pipefail

export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
export AIDER_MODEL="${AIDER_MODEL:-ollama_chat/qwen2.5-coder:7b}"
export AIDER_WEAK_MODEL="${AIDER_WEAK_MODEL:-ollama_chat/qwen2.5-coder:7b}"

unset OPENAI_API_KEY
unset ANTHROPIC_API_KEY
unset GOOGLE_API_KEY
unset OPENROUTER_API_KEY
unset DEEPSEEK_API_KEY
unset XAI_API_KEY
unset GROQ_API_KEY
unset MISTRAL_API_KEY

exec aider --model "$AIDER_MODEL" "$@"
