#!/usr/bin/env bash
# HELP_CMD=cleanup
# HELP_FLAGS=-h --help -keep N -k N
# HELP_DESC=Clean generations and run GC; with keep, retain the latest N generations.
# HELP_EXAMPLE=cleanup -keep 5
set -euo pipefail

keep_count=0

show_help() {
  cat <<'EOF'
Usage: cleanup [FLAGS]

Flags:
  -h, --help        Show this help text
  -keep N           Keep the latest N generations (e.g. -keep 5)
  -k N              Short form of -keep

Behavior:
  - Without -keep: run full cleanup of old generations + GC.
  - With -keep N: keep latest N system generations, then GC unreachable store paths.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -keep|-k)
      shift
      if [ "$#" -eq 0 ] || ! echo "$1" | grep -Eq '^[0-9]+$'; then
        echo "[ERROR] -keep requires a numeric value."
        echo "Try: cleanup --help"
        exit 1
      fi
      keep_count="$1"
      ;;
    *)
      echo "[ERROR] Unknown flag: $1"
      echo "Try: cleanup --help"
      exit 1
      ;;
  esac
  shift
done

if [ "$keep_count" -gt 0 ]; then
  sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +"$keep_count"
  nix store gc || true
  sudo nix store gc || true
else
  nix-collect-garbage --delete-old
  sudo nix-collect-garbage -d
fi

sudo /run/current-system/bin/switch-to-configuration boot
