#!/usr/bin/env bash
# HELP_CMD=thermal-status
# HELP_FLAGS=<none>
# HELP_DESC=Print a quick thermal, power, CPU, and GPU snapshot for debugging.
# HELP_EXAMPLE=thermal-status
set -euo pipefail

echo "== uptime =="
uptime
echo

echo "== sensors =="
sensors || true
echo

echo "== power profile =="
powerprofilesctl get 2>/dev/null || true
echo

echo "== top cpu =="
ps -eo pid,ppid,user,comm,%cpu,%mem --sort=-%cpu | head -n 20
echo

echo "== gpu =="
for f in /sys/class/drm/card*/device/gpu_busy_percent /sys/class/drm/card*/device/power_dpm_force_performance_level /sys/class/drm/card*/device/power_dpm_state /sys/class/drm/card*/device/pp_dpm_sclk; do
  [ -e "$f" ] || continue
  echo "-- $f --"
  cat "$f" 2>/dev/null || true
done
