#!/usr/bin/env bash
# HELP_CMD=lamabuddy
# HELP_FLAGS=[aider arguments...]
# HELP_DESC=Launch aider against the local Ollama server with the default qwen2.5-coder profile.
# HELP_EXAMPLE=lamabuddy
set -euo pipefail

export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://localhost:11434}"
exec aider --model ollama_chat/qwen2.5-coder:7b "$@"
