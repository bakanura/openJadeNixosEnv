#!/usr/bin/env bash
# HELP_CMD=thermal-test
# HELP_FLAGS=<off|on|status> <vscode|teams|firefox>
# HELP_DESC=Pause, resume, or inspect likely heat sources by app target.
# HELP_EXAMPLE=thermal-test status firefox
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: thermal-test <off|on|status> <vscode|teams|firefox>"
  exit 1
fi

action="$1"
target="$2"

case "$target" in
  vscode)
    pattern='(^|/)(code|codex)$|vscode'
    ;;
  teams)
    pattern='teams-for-linux|electron'
    ;;
  firefox)
    pattern='(^|/)(firefox|\.firefox-wrapper)$|Isolated Web Co|WebExtensions'
    ;;
  *)
    echo "Unknown target: $target"
    exit 1
    ;;
esac

pids="$(pgrep -f "$pattern" || true)"

case "$action" in
  off)
    if [ -z "$pids" ]; then
      echo "No matching processes for $target"
      exit 0
    fi
    echo "$pids" | xargs -r kill -STOP
    ;;
  on)
    if [ -z "$pids" ]; then
      echo "No matching processes for $target"
      exit 0
    fi
    echo "$pids" | xargs -r kill -CONT
    ;;
  status)
    if [ -z "$pids" ]; then
      echo "No matching processes for $target"
      exit 0
    fi
    ps -o pid,stat,comm,args= -p $(echo "$pids" | tr '\n' ' ')
    ;;
  *)
    echo "Unknown action: $action"
    exit 1
    ;;
esac
