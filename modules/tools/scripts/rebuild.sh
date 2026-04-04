#!/usr/bin/env bash
# HELP_CMD=rebuild
# HELP_FLAGS=[--quiet-summary|--full-summary] [--verbose-build]
# HELP_DESC=Compatibility wrapper for update --rebuild.
# HELP_EXAMPLE=rebuild --quiet-summary
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/update.sh" --rebuild "$@"
