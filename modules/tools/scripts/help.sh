#!/usr/bin/env bash
# HELP_CMD=helpme
# HELP_FLAGS=--text
# HELP_DESC=Show the custom command library; opens a GUI list when available.
# HELP_EXAMPLE=helpme
set -euo pipefail

show_text=0
if [ "${1:-}" = "--text" ]; then
  show_text=1
fi

scripts_dir="__SCRIPTS_DIR__"

extra_rows=(
  $'usb-guard\t--review --watch --queue --approve ID [--permanent] --release UUID --audit\tUnified USBGuard review, unblock/release, queue, and audit control.\tusb-guard --queue'
)

escape_markup() {
  local s=${1:-}
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

trim_field() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

append_row() {
  local cmd="$1"
  local flags="$2"
  local desc="$3"
  local example="$4"
  rows+=("$(printf '%s\t%s\t%s\t%s' "$cmd" "$flags" "$desc" "$example")")
}

load_rows() {
  rows=()
  local script line cmd flags desc example

  if [ -d "$scripts_dir" ]; then
    while IFS= read -r -d '' script; do
      cmd=""
      flags=""
      desc=""
      example=""

      while IFS= read -r line; do
        case "$line" in
          '# HELP_CMD='*)
            cmd="$(trim_field "${line#\# HELP_CMD=}")"
            ;;
          '# HELP_FLAGS='*)
            flags="$(trim_field "${line#\# HELP_FLAGS=}")"
            ;;
          '# HELP_DESC='*)
            desc="$(trim_field "${line#\# HELP_DESC=}")"
            ;;
          '# HELP_EXAMPLE='*)
            example="$(trim_field "${line#\# HELP_EXAMPLE=}")"
            ;;
        esac
      done <"$script"

      if [ -n "$cmd" ]; then
        append_row "$cmd" "${flags:-<none>}" "$desc" "$example"
      fi
    done < <(find "$scripts_dir" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
  fi

  local row
  for row in "${extra_rows[@]}"; do
    rows+=("$row")
  done
}

print_text_table() {
  printf "%-16s %-56s %-64s %s\n" "COMMAND" "FLAGS" "DESCRIPTION" "EXAMPLE"
  printf "%-16s %-56s %-64s %s\n" "-------" "-----" "-----------" "-------"
  local row c f d e
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r c f d e <<<"$row"
    printf "%-16s %-56s %-64s %s\n" "$c" "$f" "$d" "$e"
  done
}

show_details() {
  local cmd="$1"
  local row c f d e

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r c f d e <<<"$row"
    if [ "$c" = "$cmd" ]; then
      yad \
        --text-info \
        --title="Command: $c" \
        --width=800 \
        --height=400 \
        --center \
        --button=OK:0 \
        --filename=<(cat <<EOF
COMMAND
  $c

FLAGS
  $f

DESCRIPTION
  $d

EXAMPLE
  $e
EOF
)
      return
    fi
  done
}

run_yad() {
  local args=()
  local row c f d e selection cmd rc

  args=(
    --list
    --title=Custom\ Command\ Library
    --width=1180
    --height=680
    --center
    --search-column=1
    --column=Command
    --column=Flags
    --column=Description
    --column=Example
    --button=Done:1
    --button=Open:0
    --
  )

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r c f d e <<<"$row"
    args+=(
      "$(escape_markup "$c")"
      "$(escape_markup "$f")"
      "$(escape_markup "$d")"
      "$(escape_markup "$e")"
    )
  done

  while true; do
    selection="$(yad "${args[@]}" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      return
    fi

    cmd="$(echo "$selection" | cut -d'|' -f1)"
    if [ -n "$cmd" ]; then
      show_details "$cmd"
    fi
  done
}

main() {
  load_rows

  if [ "$show_text" -eq 0 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if command -v yad >/dev/null 2>&1; then
      run_yad >/dev/null 2>&1 &
      disown
      exit 0
    fi
  fi

  print_text_table
}

main "$@"
