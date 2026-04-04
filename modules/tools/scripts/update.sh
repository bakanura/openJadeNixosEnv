#!/usr/bin/env bash
# HELP_CMD=update
# HELP_FLAGS=[--firmware] [--rebuild] [--quiet-summary|--full-summary] [--verbose-build]
# HELP_DESC=Unified updater: refresh flake inputs, firmware only, or update and rebuild with --rebuild.
# HELP_EXAMPLE=update --rebuild --full-summary
set -euo pipefail

cd "__REPO_ROOT__"
export NIX_CONFIG=$'experimental-features = nix-command flakes\nwarn-dirty = false'

summary_mode="normal"
build_mode="quiet"
run_firmware=0
run_rebuild=0
SUDO_KEEPALIVE_PID=""
SPINNER_PID=""
SPINNER_MSG=""

cleanup() {
  if [ -n "${SPINNER_PID:-}" ]; then
    kill "$SPINNER_PID" >/dev/null 2>&1 || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}
trap cleanup EXIT INT TERM

start_spinner() {
  local msg="${1:-Working...}"
  stop_spinner || true
  SPINNER_MSG="$msg"

  (
    chars='|/-\'
    i=0
    while true; do
      c="${chars:i%4:1}"
      printf '\r[%s] %s' "$c" "$msg"
      i=$((i + 1))
      sleep 0.12
    done
  ) &
  SPINNER_PID="$!"
}

stop_spinner() {
  if [ -n "${SPINNER_PID:-}" ]; then
    kill "$SPINNER_PID" >/dev/null 2>&1 || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf '\r\033[2K'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --firmware)
      run_firmware=1
      ;;
    --rebuild)
      run_rebuild=1
      ;;
    --quiet-summary)
      summary_mode="quiet"
      ;;
    --full-summary)
      summary_mode="full"
      ;;
    --verbose-build)
      build_mode="verbose"
      ;;
    *)
      echo "[ERROR] Unknown flag: $1"
      echo "Usage: update [--firmware] [--rebuild] [--quiet-summary|--full-summary] [--verbose-build]"
      exit 1
      ;;
  esac
  shift
done

run_firmware_updates() {
  if ! command -v fwupdmgr >/dev/null 2>&1; then
    echo "[WARN] fwupdmgr not found; skipping firmware step."
    return 0
  fi

  echo "[INFO] Refreshing firmware metadata..."
  sudo fwupdmgr refresh --force
  echo "[INFO] Listing firmware-capable devices..."
  sudo fwupdmgr get-devices || true
  echo "[INFO] Checking available firmware updates..."
  sudo fwupdmgr get-updates || true

  read -r -p "Apply available firmware updates now? (y/N): " ans </dev/tty || true
  if echo "${ans:-n}" | grep -qi '^y'; then
    sudo fwupdmgr update
  else
    echo "[INFO] Skipped firmware update."
  fi
}

ensure_sudo_session() {
  if ! command -v sudo >/dev/null 2>&1; then
    echo "[ERROR] sudo not found."
    exit 1
  fi

  echo "[INFO] Authenticating for privileged operations..."
  sudo -v

  (
    while true; do
      sleep 50
      sudo -n true >/dev/null 2>&1 || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

# Ensure untracked/new files are included in flake source snapshot.
git add . >/dev/null 2>&1 || true

before_system="$(readlink -f /run/current-system || true)"
runtime_host="$(sed -n 's/^[[:space:]]*host[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' flake.nix | head -n1)"
if [ -z "$runtime_host" ]; then
  runtime_host="__DEFAULT_HOST__"
fi

run_inputs_update=1
if [ "$run_firmware" -eq 1 ] || [ "$run_rebuild" -eq 1 ]; then
  run_inputs_update=0
fi

if [ "$run_inputs_update" -eq 1 ]; then
  echo "[INFO] Updating flake inputs..."
  nix flake update
fi

if [ "$run_firmware" -eq 1 ]; then
  run_firmware_updates
fi

if [ "$run_rebuild" -eq 0 ]; then
  echo "-----"
  echo "[INFO] Update summary (auto-generated)"
  echo "Format: v2"
  echo "Inputs updated: $run_inputs_update"
  echo "Firmware: $run_firmware"
  echo "Rebuild: false"
  echo "Host: $runtime_host"
  exit 0
fi

echo "[INFO] Starting rebuild for host: $runtime_host"
echo "[INFO] Build mode: $build_mode"
echo "[INFO] Summary mode: $summary_mode"

ensure_sudo_session

if ! command -v nh >/dev/null 2>&1; then
  echo "[ERROR] nh not found in PATH."
  exit 1
fi

if [ "$build_mode" = "verbose" ]; then
  nh os switch -u -H "$runtime_host" .
else
  build_log="$(mktemp -t update-rebuild.XXXXXX.log)"
  echo "[INFO] Quiet mode enabled. Live build output is hidden."
  echo "[INFO] Writing full build log to: $build_log"

  start_spinner "Rebuilding NixOS for $runtime_host..."

  if ! nh os switch -u -H "$runtime_host" . >"$build_log" 2>&1; then
    stop_spinner
    echo "[ERROR] Rebuild failed. Showing last 120 lines:"
    tail -n 120 "$build_log" || true
    echo "[ERROR] Full log kept at: $build_log"
    exit 1
  fi

  stop_spinner
  echo "[INFO] Rebuild completed successfully."
  rm -f "$build_log"
fi

after_system="$(readlink -f /run/current-system || true)"

format_diff_summary() {
  local raw="$1"

  if [ -z "$raw" ]; then
    echo "No package-level closure diffs reported."
    return 0
  fi

  if [ "$summary_mode" = "quiet" ]; then
    echo "Changed packages: $(printf "%s\n" "$raw" | wc -l | tr -d ' ') entries"
    return 0
  fi

  if [ "$summary_mode" = "full" ]; then
    echo "Changed packages (full):"
    printf "%s\n" "$raw" \
      | sed -e 's/∅/<none>/g' -e 's/ε/<no-version>/g' \
      | sed 's/^/  - /'
    if printf "%s\n" "$raw" | grep -q '∅ → ε'; then
      echo
      echo "Note: '<none> -> <no-version>' usually means a local unversioned script/package was added."
    fi
    return 0
  fi

  echo "Changed packages (top 40):"
  printf "%s\n" "$raw" \
    | sed -e 's/∅/<none>/g' -e 's/ε/<no-version>/g' \
    | sed -n '1,40p' \
    | sed 's/^/  - /'

  if printf "%s\n" "$raw" | grep -q '∅ → ε'; then
    echo
    echo "Note: '<none> -> <no-version>' usually means a local unversioned script/package was added."
  fi
}

echo "-----"
echo "[INFO] Rebuild summary (auto-generated)"
echo "Format: v2"
echo "Inputs updated: $run_inputs_update"
echo "Firmware: $run_firmware"
echo "Rebuild: true"
echo "Build mode: $build_mode"
echo "Summary mode: $summary_mode"
echo "Host: $runtime_host"
echo "Before: ${before_system:-<unknown>}"
echo "After : ${after_system:-<unknown>}"

if [ -n "${before_system:-}" ] && [ -n "${after_system:-}" ] && [ "$before_system" != "$after_system" ]; then
  echo
  if [ "$summary_mode" = "full" ]; then
    diff_output="$(nix store diff-closures "$before_system" "$after_system" || true)"
  else
    diff_output="$(nix store diff-closures "$before_system" "$after_system" | sed -n '1,140p' || true)"
  fi
  format_diff_summary "$diff_output"
elif [ "$before_system" = "$after_system" ] && [ -n "${before_system:-}" ]; then
  echo "No closure change detected (same /run/current-system target)."
else
  echo "Could not compute closure diff."
fi