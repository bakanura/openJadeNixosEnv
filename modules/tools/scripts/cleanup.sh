#!/usr/bin/env bash
# HELP_CMD=cleanup
# HELP_FLAGS=-h --help -keep N -k N
# HELP_DESC=Clean generations and run GC; with keep, retain the latest N generations and newest rebuild logs.
# HELP_EXAMPLE=cleanup -keep 5
set -euo pipefail

keep_count=0
log_dir="/tmp"
log_name_glob="update-rebuild.*.log"

show_help() {
  cat <<'EOF'
Usage: cleanup [FLAGS]

Flags:
  -h, --help        Show this help text
  -keep N           Keep the latest N generations and latest N rebuild logs
  -k N              Short form of -keep

Behavior:
  - Without -keep: run full cleanup of old generations + GC, and remove all rebuild logs.
  - With -keep N: keep latest N system generations, keep latest N rebuild logs, then GC unreachable store paths.
EOF
}

cleanup_rebuild_logs() {
  local keep="$1"
  local -a log_files=()

  while IFS= read -r file; do
    [ -n "$file" ] && log_files+=("$file")
  done < <(find "$log_dir" -maxdepth 1 -type f -name "$log_name_glob" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{ $1=""; sub(/^ /, ""); print }')

  if [ "${#log_files[@]}" -eq 0 ]; then
    return 0
  fi

  if [ "$keep" -le 0 ]; then
    rm -f -- "${log_files[@]}"
    return 0
  fi

  if [ "${#log_files[@]}" -le "$keep" ]; then
    return 0
  fi

  for old_log in "${log_files[@]:$keep}"; do
    rm -f -- "$old_log"
  done
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

cleanup_rebuild_logs "$keep_count"

sudo /run/current-system/bin/switch-to-configuration boot