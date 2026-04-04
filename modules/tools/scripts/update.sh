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

if [ "$build_mode" = "verbose" ]; then
  nh os switch -u -H "$runtime_host" .
else
  build_log="$(mktemp)"
  if ! nh os switch -u -H "$runtime_host" . >"$build_log" 2>&1; then
    echo "[ERROR] Rebuild failed. Showing last 120 lines:"
    tail -n 120 "$build_log" || true
    rm -f "$build_log"
    exit 1
  fi
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
    echo "Changed packages: $(printf "%s\n" "$raw" | wc -l) entries"
    return 0
  fi
  if [ "$summary_mode" = "full" ]; then
    echo "Changed packages (full):"
    printf "%s\n" "$raw" | sed -e 's/∅/<none>/g' -e 's/ε/<no-version>/g' | sed 's/^/  - /'
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
