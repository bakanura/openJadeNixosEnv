#!/usr/bin/env bash
# Common installer helpers for NixOS-Hyprland
# Sourced by install.sh and auto-install.sh
#
# Host path model:
#   hosts/default/            = permanent template
#   .local-host/<hostname>/   = generated/current machine host
#
# IMPORTANT:
#   hosts/default/hardware.nix is NEVER used as a fallback for a generated
#   host. A missing local hardware.nix is a hard error.
#
#   A local hardware.nix which simply contains no LUKS mapping is valid.
#   This means the machine does not use LUKS and TPM/LUKS enrollment is
#   skipped without treating it as an installer failure.

nhl_repo_root() {
  if [ -n "${NHL_REPO_ROOT:-}" ] && [ -d "${NHL_REPO_ROOT}" ]; then
    printf "%s\n" "${NHL_REPO_ROOT}"
    return 0
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi

  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    local helper_dir=""
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf "%s\n" "$(cd "${helper_dir}/../.." && pwd)"
    return 0
  fi

  pwd
}

nhl_local_hosts_root() {
  # Keep one canonical location for generated machine-local hosts.
  #
  # The installer historically uses .local-host. Allow callers to override
  # this explicitly if required, but do not silently switch locations.
  printf "%s\n" "${NHL_LOCAL_HOSTS_ROOT:-.local-host}"
}

nhl_local_host_dir() {
  # Args: $1 = hostName
  local hostName="$1"
  local root=""

  root=$(nhl_local_hosts_root)

  printf "%s\n" "${root}/${hostName}"
}

nhl_patch_flake_identity() {
  # Backward-compatible helper name. It now writes host identity JSON.
  # Args: $1 = repo root, $2 = hostName, $3 = username
  local repoRoot="$1"
  local hostName="$2"
  local installUsername="$3"
  local identityFile="${repoRoot}/.local-host/${hostName}/identity.json"

  # Safety check: do not overwrite a real user with the bootstrap fallback
  # if the file already exists.
  if [ "$installUsername" = "nixos-bootstrap" ] &&
     [ -f "$identityFile" ]; then

    local existing
    existing=$(
      grep -oP '"username":\s*"\K[^"]+' "$identityFile" ||
        echo ""
    )

    if [ -n "$existing" ] &&
       [ "$existing" != "nixos-bootstrap" ]; then

      echo "[WARN] Refusing to overwrite existing user '$existing' with 'nixos-bootstrap' in identity file."
      return 0
    fi
  fi

  mkdir -p "$(dirname "$identityFile")"

  cat >"$identityFile" <<EOF
{
  "username": "$installUsername"
}
EOF
}

nhl_print_postinstall_notes() {
  # Args: $1 = repo root, $2 = hostName
  local repoRoot="$1"
  local hostName="$2"

  printf "%s\n" "-----"
  printf "%s\n" "[INFO] Installer follow-ups"
  printf "%s\n" "- USBGuard dock approvals are handled at runtime; if a dock blocks first, approve the dock helper/hub chain and storage-capable children will be reviewed separately afterward."
  printf "%s\n" "- Custom UI translation can use a per-host encrypted DeepL key. Optional bootstrap command:"
  printf "%s\n" "  cd ${repoRoot} && custom-ui-translation-bootstrap-secret ${hostName}"
  printf "%s\n" "- That writes secrets/${hostName}/deepl-api-key.age for future rebuilds on this laptop."
}

nhl_is_noninteractive() {
  if [ "${NHL_NONINTERACTIVE:-0}" = "1" ] ||
     [ "${INTUNE_MANAGED:-0}" = "1" ] ||
     [ -n "${INTUNE_DEVICE_ID:-}" ] ||
     [ ! -r /dev/tty ]; then
    return 0
  fi

  return 1
}

nhl_read_input() {
  # Args: $1 = prompt, $2 = default value
  local prompt="$1"
  local defaultValue="${2:-}"
  local ans=""

  if nhl_is_noninteractive; then
    printf "%s\n" "$defaultValue"
    return 0
  fi

  read -rp "$prompt" ans </dev/tty || true

  if [ -z "$ans" ]; then
    ans="$defaultValue"
  fi

  printf "%s\n" "$ans"
}

nhl_yes_no() {
  # Args: $1 = prompt, returns success for yes.
  local prompt="$1"
  local ans=""

  if nhl_is_noninteractive; then
    return 0
  fi

  read -rp "$prompt" ans </dev/tty || true

  if [ -z "$ans" ] || echo "$ans" | grep -qi '^y'; then
    return 0
  fi

  return 1
}

nhl_resolve_install_username() {
  # 1. Check SUDO_USER (most reliable when running via sudo)
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    if id "$SUDO_USER" >/dev/null 2>&1; then
      printf "%s\n" "$SUDO_USER"
      return 0
    fi
  fi

  # 2. Check current USER
  if [ -n "${USER:-}" ] && [ "$USER" != "root" ]; then
    if id "$USER" >/dev/null 2>&1; then
      printf "%s\n" "$USER"
      return 0
    fi
  fi

  # 3. Last ditch check of current effective ID
  local current_id_name
  current_id_name=$(id -un 2>/dev/null || true)

  if [ -n "$current_id_name" ] &&
     [ "$current_id_name" != "root" ]; then

    printf "%s\n" "$current_id_name"
    return 0
  fi

  # 4. Fallback for non-interactive automation
  if nhl_is_noninteractive; then
    printf "nixos-bootstrap\n"
    return 0
  fi

  # 5. Interactive fallback: Use the first UID 1000 user found.
  local real_user
  real_user=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd | head -n1)

  printf "%s\n" "${real_user:-roederp}"
}

nhl_detect_host_serial() {
  local serial=""

  if [ -r /sys/class/dmi/id/product_serial ]; then
    serial=$(
      tr -d '[:space:]' </sys/class/dmi/id/product_serial 2>/dev/null ||
        true
    )
  fi

  if [ -z "$serial" ] &&
     [ -r /sys/devices/virtual/dmi/id/product_serial ]; then

    serial=$(
      tr -d '[:space:]' \
        </sys/devices/virtual/dmi/id/product_serial \
        2>/dev/null ||
        true
    )
  fi

  if [ -z "$serial" ] &&
     [ -r /etc/machine-id ]; then

    serial=$(cut -c1-12 /etc/machine-id 2>/dev/null || true)
  fi

  printf "%s\n" "$serial"
}

nhl_sanitize_hostname() {
  local raw="$1"
  local sanitized=""

  sanitized=$(
    printf "%s" "$raw" |
      tr '[:space:]' '-' |
      tr -cd '[:alnum:]-'
  )

  sanitized=$(
    printf "%s" "$sanitized" |
      sed 's/--*/-/g; s/^-//; s/-$//'
  )

  sanitized="${sanitized:0:63}"

  if [ -z "$sanitized" ]; then
    sanitized="UNKNOWN-HOST"
  fi

  printf "%s\n" "$sanitized"
}

nhl_resolve_console_keymap() {
  # Args: $1 = console keymap name
  #
  # Resolves a NixOS/kbd console keymap name to an actual keymap file.
  #
  # Examples:
  #   de          -> .../share/keymaps/i386/qwertz/de.map.gz
  #   de-latin1   -> .../share/keymaps/i386/qwertz/de-latin1.map.gz
  #   ru          -> .../share/keymaps/i386/qwerty/ru.map.gz
  #   ru-yawerty  -> .../share/keymaps/i386/qwerty/ru-yawerty.map.gz
  #   us          -> .../share/keymaps/i386/qwerty/us.map.gz
  #
  # IMPORTANT:
  #   Do not use `loadkeys -p "$file"` here.
  #   The keymap files are valid even when loadkeys cannot resolve
  #   their Nix store path/includes correctly.
  #
  # Return:
  #   0 = keymap found
  #   1 = keymap not found

  local keymap="${1:-}"
  local kbd=""
  local keymaps_root=""
  local found=""

  if [ -z "$keymap" ]; then
    return 1
  fi

  # Prevent path traversal / accidental path input.
  if ! printf "%s" "$keymap" |
    grep -qE '^[[:alnum:]_-]+$'; then
    return 1
  fi

  # Prefer the Nixpkgs kbd package.
  if command -v nix >/dev/null 2>&1; then
    kbd=$(
      NIX_CONFIG="experimental-features = nix-command flakes" \
        nix eval --raw nixpkgs#kbd 2>/dev/null ||
        true
    )
  fi

  if [ -n "$kbd" ] &&
     [ -d "$kbd/share/keymaps" ]; then

    keymaps_root="$kbd/share/keymaps"
  elif [ -d "/run/current-system/sw/share/keymaps" ]; then
    keymaps_root="/run/current-system/sw/share/keymaps"
  elif [ -d "/usr/share/keymaps" ]; then
    keymaps_root="/usr/share/keymaps"
  else
    return 1
  fi

  found=$(
    find "$keymaps_root" -type f \
      \( \
        -name "${keymap}.map" \
        -o -name "${keymap}.map.gz" \
        -o -name "${keymap}.map.bz2" \
        -o -name "${keymap}.map.xz" \
        -o -name "${keymap}.map.lz" \
        -o -name "${keymap}.map.lz4" \
        -o -name "${keymap}.map.zst" \
      \) \
      -print -quit 2>/dev/null
  )

  if [ -n "$found" ]; then
    printf "%s\n" "$found"
    return 0
  fi

  return 1
}

nhl_derive_hostname() {
  # Args: $1 = optional prefix (default: NixOS)
  local prefix="${1:-NixOS}"
  local serial=""
  local serial_clean=""
  local hostName=""

  serial=$(nhl_detect_host_serial)

  serial_clean=$(echo "$serial" | tr -cd '[:alnum:]')

  if [ -z "$serial_clean" ]; then
    serial_clean="UNKNOWN"
  fi

  hostName="${prefix}-${serial_clean}"
  hostName=$(nhl_sanitize_hostname "$hostName")

  printf "%s\n" "$hostName"
}

nhl_prompt_hostname() {
  local default_prefix="${1:-NixOS}"
  local serial=""
  local serial_clean=""
  local mode=""
  local prefix=""
  local custom=""

  serial=$(nhl_detect_host_serial)

  serial_clean=$(printf "%s" "$serial" | tr -cd '[:alnum:]')

  if [ -z "$serial_clean" ]; then
    serial_clean="UNKNOWN"
  fi

  if nhl_is_noninteractive; then
    export NHL_SELECTED_HOSTNAME_MODE="prefix-serial"

    export NHL_SELECTED_HOSTNAME_PREFIX="$(
      nhl_sanitize_hostname \
        "${NHL_STATE_HOSTNAME_PREFIX:-$default_prefix}"
    )"

    export NHL_SELECTED_HOSTNAME_VALUE="$(
      nhl_derive_hostname "${NHL_SELECTED_HOSTNAME_PREFIX}"
    )"

    printf "%s\n" "${NHL_SELECTED_HOSTNAME_VALUE}"
    return 0
  fi

  while true; do
    mode=$(nhl_read_input \
      "Choose hostname style: [s]yntax + serial / [u]nique name (required): " \
      "")

    if printf "%s" "$mode" | grep -qi '^[uUcC]'; then
      custom=$(nhl_read_input \
        "Enter the exact hostname to use (no serial will be appended): " \
        "${NHL_STATE_HOSTNAME_VALUE:-}")

      custom=$(nhl_sanitize_hostname "$custom")

      if [ -z "$custom" ] ||
         [ "$custom" = "UNKNOWN-HOST" ]; then

        printf '%s\n' \
          "[WARN] Please enter a non-empty hostname." \
          >&2
        continue
      fi

      export NHL_SELECTED_HOSTNAME_MODE="custom"
      export NHL_SELECTED_HOSTNAME_VALUE="$custom"

      printf "%s\n" "${NHL_SELECTED_HOSTNAME_VALUE}"
      return 0
    fi

    if printf "%s" "$mode" | grep -qi '^[sSpP]'; then
      break
    fi

    printf '%s\n' \
      "[WARN] Please choose 's' for syntax + serial or 'u' for a unique hostname." \
      >&2
  done

  while true; do
    prefix=$(nhl_read_input \
      "Enter the hostname syntax/prefix to combine with this device serial (${serial_clean}): " \
      "${NHL_STATE_HOSTNAME_PREFIX:-$default_prefix}")

    prefix=$(nhl_sanitize_hostname "$prefix")

    if [ -n "$prefix" ] &&
       [ "$prefix" != "UNKNOWN-HOST" ]; then
      break
    fi

    printf '%s\n' \
      "[WARN] Please enter a non-empty hostname syntax/prefix." \
      >&2
  done

  export NHL_SELECTED_HOSTNAME_MODE="prefix-serial"
  export NHL_SELECTED_HOSTNAME_PREFIX="$prefix"

  export NHL_SELECTED_HOSTNAME_VALUE="$(
    nhl_derive_hostname "${NHL_SELECTED_HOSTNAME_PREFIX}"
  )"

  printf "%s\n" "${NHL_SELECTED_HOSTNAME_VALUE}"
}

nhl_preflight_install_repo() {
  local repoRoot="${1:-$(pwd)}"
  local missing=0

  for path in \
    flake.nix \
    install.sh \
    auto-install.sh \
    hosts/default/config.nix \
    hosts/default/variables.nix \
    hosts/default/users.nix \
    hosts/default/packages-fonts.nix \
    hosts/default/hardware.nix \
    scripts/lib/install-common.sh; do

    if [ ! -e "${repoRoot}/${path}" ]; then
      echo "[ERROR] Missing required installer path: ${path}"
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    return 1
  fi

  return 0
}

nhl_preflight_fresh_install_target() {
  # Args: $1 = repo root, $2 = hostName
  local repoRoot="$1"
  local hostName="$2"
  local hostDir="${repoRoot}/.local-host/${hostName}"

  if [ ! -d "${repoRoot}/hosts/default" ]; then
    echo "[ERROR] Missing hosts/default template directory."
    return 1
  fi

  if [ -e "$hostDir" ] &&
     [ ! -d "$hostDir" ]; then

    echo "[ERROR] Target host path exists but is not a directory: $hostDir"
    return 1
  fi

  if [ -d "$hostDir" ] &&
     [ -z "$(find "$hostDir" -maxdepth 1 -type f 2>/dev/null)" ]; then

    echo "[WARN] Target host directory exists but looks incomplete: $hostDir"
  fi

  return 0
}

nhl_is_enrolled_device() {
  # Args: $1 = hostName
  local hostName="$1"
  local marker=".local-host/$hostName/.nhl-enrolled"
  local mid=""

  if [ ! -f "$marker" ]; then
    return 1
  fi

  if [ -r /etc/machine-id ]; then
    mid=$(cat /etc/machine-id 2>/dev/null || true)
  fi

  if [ -z "$mid" ]; then
    return 0
  fi

  if grep -q "^machine_id=$mid$" "$marker" 2>/dev/null; then
    return 0
  fi

  return 1
}

nhl_mark_device_enrolled() {
  # Args: $1 = hostName
  local hostName="$1"
  local hostDir=".local-host/$hostName"
  local marker="${hostDir}/.nhl-enrolled"
  local mid=""
  local serial=""

  if [ -r /etc/machine-id ]; then
    mid=$(cat /etc/machine-id 2>/dev/null || true)
  fi

  if [ -r /sys/class/dmi/id/product_serial ]; then
    serial=$(
      tr -d '[:space:]' </sys/class/dmi/id/product_serial 2>/dev/null ||
        true
    )
  fi

  mkdir -p "$hostDir"

  cat >"$marker" <<EOF
machine_id=$mid
serial=$serial
enrolled_at=$(date -Iseconds)
EOF
}

nhl_state_file() {
  # Args: $1 = hostName
  local hostName="$1"

  printf ".local-host/%s/.installer-state.json\n" "$hostName"
}

nhl_load_installer_state() {
  # Args: $1 = hostName
  local hostName="$1"
  local stateFile

  stateFile=$(nhl_state_file "$hostName")

  unset \
    NHL_STATE_GPU_PROFILE \
    NHL_STATE_KEYBOARD_LAYOUT \
    NHL_STATE_TIMEZONE \
    NHL_STATE_CONSOLE_KEYMAP \
    NHL_STATE_FINGERPRINT \
    NHL_STATE_VSCODE_CONFIRM_SYNC \
    NHL_STATE_HOSTNAME_MODE \
    NHL_STATE_HOSTNAME_PREFIX \
    NHL_STATE_HOSTNAME_VALUE

  if [ ! -f "$stateFile" ]; then
    return 1
  fi

  NHL_STATE_GPU_PROFILE=$(
    sed -n \
      's/.*"gpu_profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_KEYBOARD_LAYOUT=$(
    sed -n \
      's/.*"keyboard_layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_TIMEZONE=$(
    sed -n \
      's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_CONSOLE_KEYMAP=$(
    sed -n \
      's/.*"console_keymap"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_FINGERPRINT=$(
    sed -n \
      's/.*"fingerprint_enabled"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_VSCODE_CONFIRM_SYNC=$(
    sed -n \
      's/.*"vscode_confirm_sync"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_HOSTNAME_MODE=$(
    sed -n \
      's/.*"hostname_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_HOSTNAME_PREFIX=$(
    sed -n \
      's/.*"hostname_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  NHL_STATE_HOSTNAME_VALUE=$(
    sed -n \
      's/.*"hostname_value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$stateFile" |
      head -n1
  )

  export \
    NHL_STATE_GPU_PROFILE \
    NHL_STATE_KEYBOARD_LAYOUT \
    NHL_STATE_TIMEZONE \
    NHL_STATE_CONSOLE_KEYMAP \
    NHL_STATE_FINGERPRINT \
    NHL_STATE_VSCODE_CONFIRM_SYNC \
    NHL_STATE_HOSTNAME_MODE \
    NHL_STATE_HOSTNAME_PREFIX \
    NHL_STATE_HOSTNAME_VALUE

  return 0
}

nhl_save_installer_state() {
  # Args:
  # $1 hostName
  # $2 keyboard
  # $3 timezone
  # $4 console keymap
  # $5 fingerprint(0/1)
  # $6 gpu profile
  # $7 vscode confirm sync(true/false)
  # $8 hostname mode
  # $9 hostname prefix
  # $10 hostname value

  local hostName="$1"
  local keyboardLayout="$2"
  local timeZone="$3"
  local consoleKeyMap="$4"
  local fingerprintEnabled="$5"
  local gpuProfile="$6"
  local vscodeConfirmSync="${7:-true}"
  local hostnameMode="${8:-prefix-serial}"
  local hostnamePrefix="${9:-NixOS}"
  local hostnameValue="${10:-$hostName}"
  local stateFile
  local fpJson="false"

  stateFile=$(nhl_state_file "$hostName")

  mkdir -p ".local-host/$hostName"

  if [ "$fingerprintEnabled" = "1" ] ||
     [ "$fingerprintEnabled" = "true" ]; then
    fpJson="true"
  fi

  cat >"$stateFile" <<EOF
{
  "host": "$hostName",
  "gpu_profile": "$gpuProfile",
  "keyboard_layout": "$keyboardLayout",
  "console_keymap": "$consoleKeyMap",
  "timezone": "$timeZone",
  "fingerprint_enabled": $fpJson,
  "vscode_confirm_sync": $vscodeConfirmSync,
  "hostname_mode": "$hostnameMode",
  "hostname_prefix": "$hostnamePrefix",
  "hostname_value": "$hostnameValue",
  "updated_at": "$(date -Iseconds)"
}
EOF
}

nhl_detect_gpu_and_toggle() {
  # Args: $1 = hostName
  local hostName="$1"
  local cfg=""

  cfg=$(nhl_host_config_path "$hostName")

  local has_vm=false
  local has_nvidia=false
  local has_amd=false
  local has_intel=false

  if hostnamectl 2>/dev/null | grep -q 'Chassis: vm'; then
    has_vm=true
  fi

  if command -v lspci >/dev/null 2>&1; then
    while read -r line; do
      if echo "$line" | grep -qi 'nvidia'; then
        has_nvidia=true
      elif echo "$line" | grep -qi 'amd'; then
        has_amd=true
      elif echo "$line" | grep -qi 'intel'; then
        has_intel=true
      fi
    done < <(lspci | grep -iE '(VGA|3D)')
  fi

  local detected=""

  if $has_vm; then
    detected="vm"
  elif $has_nvidia && $has_intel; then
    detected="nvidia-laptop"
  elif $has_nvidia; then
    detected="nvidia"
  elif $has_amd; then
    detected="amd"
  elif $has_intel; then
    detected="intel"
  fi

  local profile="$detected"

  if [ -n "$detected" ]; then
    if ! nhl_yes_no \
      "Detected GPU profile: ${detected}. Use this? (Y/n): "; then
      profile=""
    fi
  fi

  if [ -z "$profile" ]; then
    local default_profile="${NHL_STATE_GPU_PROFILE:-amd}"

    profile=$(nhl_read_input \
      "Enter your GPU profile (amd|intel|nvidia|nvidia-laptop|vm): [${default_profile}] " \
      "$default_profile")
  fi

  nhl_sed_file \
    "$cfg" \
    -e 's/drivers\.amdgpu\.enable = [^;]*;/drivers.amdgpu.enable = false;/' ||
    true

  nhl_sed_file \
    "$cfg" \
    -e 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = false;/' ||
    true

  nhl_sed_file \
    "$cfg" \
    -e 's/drivers\.nvidia\.enable = [^;]*;/drivers.nvidia.enable = false;/' ||
    true

  nhl_sed_file \
    "$cfg" \
    -e 's/drivers\.nvidia-prime\.enable = [^;]*;/drivers.nvidia-prime.enable = false;/' ||
    true

  nhl_sed_file \
    "$cfg" \
    -e 's/vm\.guest-services\.enable = [^;]*;/vm.guest-services.enable = false;/' ||
    true

  case "$profile" in
    vm)
      nhl_sed_file \
        "$cfg" \
        -e 's/vm\.guest-services\.enable = [^;]*;/vm.guest-services.enable = true;/' ||
        true
      ;;

    nvidia-laptop)
      nhl_sed_file \
        "$cfg" \
        -e 's/drivers\.nvidia-prime\.enable = [^;]*;/drivers.nvidia-prime.enable = true;/' ||
        true

      nhl_sed_file \
        "$cfg" \
        -e 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = true;/' ||
        true
      ;;

    nvidia)
      nhl_sed_file \
        "$cfg" \
        -e 's/drivers\.nvidia\.enable = [^;]*;/drivers.nvidia.enable = true;/' ||
        true
      ;;

    amd)
      nhl_sed_file \
        "$cfg" \
        -e 's/drivers\.amdgpu\.enable = [^;]*;/drivers.amdgpu.enable = true;/' ||
        true
      ;;

    intel)
      nhl_sed_file \
        "$cfg" \
        -e 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = true;/' ||
        true
      ;;

    *)
      ;;
  esac

  export NHL_GPU_PROFILE="$profile"
}

nhl_sed_file() {
  local file="$1"
  shift

  if [ ! -f "$file" ]; then
    echo "[ERROR] Cannot modify missing file: $file"
    return 1
  fi

  local tmp=""
  local mode=""
  local owner=""
  local group=""

  tmp=$(mktemp "${TMPDIR:-/tmp}/nhl-sed.XXXXXX") || {
    echo "[ERROR] Could not create temporary file for: $file"
    return 1
  }

  mode=$(stat -c '%a' "$file" 2>/dev/null || true)
  owner=$(stat -c '%u' "$file" 2>/dev/null || true)
  group=$(stat -c '%g' "$file" 2>/dev/null || true)

  if ! sed "$@" "$file" >"$tmp"; then
    rm -f "$tmp"
    echo "[ERROR] Failed to transform: $file"
    return 1
  fi

  if [ -w "$file" ]; then
    if ! cat "$tmp" >"$file"; then
      rm -f "$tmp"
      echo "[ERROR] Failed to write modified file: $file"
      return 1
    fi

    if [ -n "$mode" ]; then
      chmod "$mode" "$file" 2>/dev/null || true
    fi
  else
    if ! sudo install -m "${mode:-644}" "$tmp" "$file"; then
      rm -f "$tmp"
      echo "[ERROR] sudo could not install modified file: $file"
      return 1
    fi

    if [ -n "$owner" ] && [ -n "$group" ]; then
      sudo chown "${owner}:${group}" "$file" 2>/dev/null || true
    fi
  fi

  rm -f "$tmp"
  return 0
}

nhl_insert_option_before_closing_brace() {
  # Args: $1 = file, $2 = full option line (including trailing ;)
  local file="$1"
  local line="$2"
  local last_brace_line

  if [ ! -f "$file" ]; then
    echo "[ERROR] Cannot modify missing file: $file"
    return 1
  fi

  last_brace_line=$(
    grep -n '^[[:space:]]*}[[:space:]]*$' "$file" |
      tail -n 1 |
      cut -d: -f1
  )

  if [ -z "$last_brace_line" ]; then
    echo "[ERROR] Could not find closing '}' in: $file"
    return 1
  fi

  local tmp=""
  local mode=""
  local owner=""
  local group=""

  tmp=$(mktemp "${TMPDIR:-/tmp}/nhl-insert.XXXXXX") || {
    echo "[ERROR] Could not create temporary file for: $file"
    return 1
  }

  mode=$(stat -c '%a' "$file" 2>/dev/null || true)
  owner=$(stat -c '%u' "$file" 2>/dev/null || true)
  group=$(stat -c '%g' "$file" 2>/dev/null || true)

  if ! awk \
    -v insert_line="$last_brace_line" \
    -v new_line="$line" '
      NR == insert_line {
        print "  " new_line
      }
      { print }
    ' "$file" >"$tmp"; then

    rm -f "$tmp"
    echo "[ERROR] Failed to insert option into: $file"
    return 1
  fi

  if [ -w "$file" ]; then
    if ! cat "$tmp" >"$file"; then
      rm -f "$tmp"
      echo "[ERROR] Failed to write modified file: $file"
      return 1
    fi

    if [ -n "$mode" ]; then
      chmod "$mode" "$file" 2>/dev/null || true
    fi
  else
    if ! sudo install -m "${mode:-644}" "$tmp" "$file"; then
      rm -f "$tmp"
      echo "[ERROR] sudo could not install modified file: $file"
      return 1
    fi

    if [ -n "$owner" ] && [ -n "$group" ]; then
      sudo chown "${owner}:${group}" "$file" 2>/dev/null || true
    fi
  fi

  rm -f "$tmp"
  return 0
}

nhl_lookup_timezone_from_city() {
  # Args: $1 = city
  local city="$1"
  local encoded=""
  local resp=""
  local tz=""

  if [ -z "$city" ] ||
     ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  encoded=$(
    printf "%s" "$city" |
      sed -e 's/%/%25/g' -e 's/ /%20/g'
  )

  resp=$(
    curl -fsSL --max-time 10 \
      "https://geocoding-api.open-meteo.com/v1/search?name=${encoded}&count=1&language=en&format=json" \
      2>/dev/null ||
      true
  )

  tz=$(
    echo "$resp" |
      tr -d '\n' |
      sed -n 's/.*"timezone":"\([^"]*\)".*/\1/p' |
      head -n1
  )

  if [ -n "$tz" ] &&
     echo "$tz" | grep -q '/'; then

    printf "%s\n" "$tz"
    return 0
  fi

  return 1
}

nhl_detect_timezone_auto() {
  local tz=""

  if command -v timedatectl >/dev/null 2>&1; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)

    if [ -n "$tz" ] &&
       [ "$tz" != "n/a" ] &&
       [ "$tz" != "UTC" ] &&
       echo "$tz" | grep -q '/'; then

      printf "%s\n" "$tz"
      return 0
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    tz=$(
      curl -fsSL --max-time 8 \
        https://ipapi.co/timezone \
        2>/dev/null |
        tr -d '[:space:]' ||
        true
    )

    if [ -n "$tz" ] &&
       echo "$tz" | grep -q '/'; then

      printf "%s\n" "$tz"
      return 0
    fi
  fi

  return 1
}

nhl_prompt_timezone_console() {
  # Args:
  #   $1 = hostName
  #   $2 = default keyboard layout
  #
  # The keyboard layout here is the NixOS/XKB-style layout that is written
  # directly to console.keyMap.
  #
  # IMPORTANT:
  # Do NOT require nhl_resolve_console_keymap() here.
  #
  # "de" is a valid NixOS console.keyMap value even when the corresponding
  # kbd keymap file cannot be resolved from the current machine's /nix/store.
  #
  # XKB keyboard layouts and kbd console keymaps are related namespaces but
  # they are not identical filesystem lookups.

  local hostName="$1"
  local defKb="${2:-us}"
  local cfg=""

  cfg=$(nhl_host_config_path "$hostName") || return 1

  local timeZone=""
  local city=""
  local manualTz=""
  local consoleKeyMap=""

  # -------------------------------------------------------------------------
  # TIMEZONE
  # -------------------------------------------------------------------------

  if [ -n "${NHL_STATE_TIMEZONE:-}" ]; then

    timeZone="$NHL_STATE_TIMEZONE"

    echo "${OK} Using saved timezone from previous installer run: ${timeZone}"

  elif timeZone=$(nhl_detect_timezone_auto); then

    echo "${OK} Detected timezone automatically: ${timeZone}"

  else

    city=$(nhl_read_input \
      "Could not auto-detect timezone. Enter your current city (e.g. Mannheim): " \
      "")

    if [ -n "$city" ]; then

      timeZone=$(nhl_lookup_timezone_from_city "$city" || true)

      if [ -n "$timeZone" ]; then
        echo "${OK} Mapped city '${city}' to timezone: ${timeZone}"
      fi

    fi

  fi

  # -------------------------------------------------------------------------
  # Manual timezone fallback
  # -------------------------------------------------------------------------

  if [ -z "$timeZone" ]; then

    manualTz=$(nhl_read_input \
      "Enter your timezone manually (e.g. Europe/Berlin), or leave blank for automatic service: [auto] " \
      "")

    timeZone="$manualTz"

  fi

  # -------------------------------------------------------------------------
  # Configure timezone
  # -------------------------------------------------------------------------

  if [ -n "$timeZone" ]; then

    if grep -q 'time\.timeZone' "$cfg"; then

      nhl_sed_file \
        "$cfg" \
        -e "s|time\.timeZone = \".*\";|time.timeZone = \"$timeZone\";|" \
        || true

    else

      nhl_insert_option_before_closing_brace \
        "$cfg" \
        "time.timeZone = \"$timeZone\";"

    fi

    # Explicit timezone means automatic timezone detection should be disabled.
    if grep -q 'services\.automatic-timezoned\.enable' "$cfg"; then

      nhl_sed_file \
        "$cfg" \
        -e 's/services\.automatic-timezoned\.enable = [^;]*/services.automatic-timezoned.enable = false/' \
        || true

    else

      nhl_insert_option_before_closing_brace \
        "$cfg" \
        "services.automatic-timezoned.enable = false;"

    fi

  else

    # No timezone selected -> allow automatic timezone detection.
    if grep -q 'services\.automatic-timezoned\.enable' "$cfg"; then

      nhl_sed_file \
        "$cfg" \
        -e 's/services\.automatic-timezoned\.enable = [^;]*/services.automatic-timezoned.enable = true/' \
        || true

    else

      nhl_insert_option_before_closing_brace \
        "$cfg" \
        "services.automatic-timezoned.enable = true;"

    fi

    nhl_sed_file \
      "$cfg" \
      -e '/time\.timeZone[[:space:]]*=/{d}' \
      || true

  fi

  # -------------------------------------------------------------------------
  # CONSOLE KEYBOARD LAYOUT
  #
  # IMPORTANT:
  #
  # Do NOT call nhl_resolve_console_keymap() here.
  #
  # The installer already validates the keyboard layout syntactically.
  # NixOS itself will resolve console.keyMap during configuration evaluation.
  #
  # This avoids machine-dependent failures such as:
  #
  #   machine A:
  #     de -> /nix/store/.../kbd/.../de.map.gz
  #
  #   machine B:
  #     de -> lookup failure
  #
  # even though "de" is a perfectly valid configuration value.
  # -------------------------------------------------------------------------

  consoleKeyMap="${NHL_STATE_CONSOLE_KEYMAP:-$defKb}"
  consoleKeyMap="${consoleKeyMap,,}"

  # Basic validation only.
  #
  # This deliberately does NOT inspect /usr/share/keymaps or /nix/store.
  if ! [[ "$consoleKeyMap" =~ ^[a-z][a-z0-9_-]*$ ]]; then

    echo "${WARN} Invalid console keyboard layout '${consoleKeyMap}'."

    if nhl_is_noninteractive; then

      echo "${ERROR} Cannot continue non-interactively with an invalid console keyboard layout."

      return 1

    fi

    while true; do

      consoleKeyMap=$(
        nhl_read_input \
          "Enter console keyboard layout (e.g. us, de, de-latin1, ru): " \
          "$defKb"
      )

      consoleKeyMap="${consoleKeyMap,,}"

      if [[ "$consoleKeyMap" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        break
      fi

      echo "${WARN} Invalid console keyboard layout '${consoleKeyMap}'."

    done

  fi

  echo "${OK} Console keymap: ${consoleKeyMap}"

  # -------------------------------------------------------------------------
  # Write console.keyMap
  # -------------------------------------------------------------------------

  if grep -q 'console\.keyMap' "$cfg"; then

    nhl_sed_file \
      "$cfg" \
      -e "s|console\.keyMap = \".*\";|console.keyMap = \"$consoleKeyMap\";|" \
      || true

  else

    nhl_insert_option_before_closing_brace \
      "$cfg" \
      "console.keyMap = \"$consoleKeyMap\";"

  fi

  # -------------------------------------------------------------------------
  # Export installer state
  # -------------------------------------------------------------------------

  export NHL_SELECTED_TIMEZONE="$timeZone"
  export NHL_SELECTED_CONSOLE_KEYMAP="$consoleKeyMap"
}

nhl_check_go_version() {
  local min_version="1.25.5"
  local nix_go_version=""
  local go_version=""

  if command -v nix >/dev/null 2>&1; then
    nix_go_version=$(
      NIX_CONFIG="experimental-features = nix-command flakes" \
        nix eval --raw "nixpkgs#go.version" 2>/dev/null ||
        true
    )
  fi

  if [ -n "$nix_go_version" ]; then
    if [ "$(printf '%s\n' "$min_version" "$nix_go_version" |
      sort -V |
      head -n1)" != "$min_version" ]; then

      echo "${ERROR} Go in nixpkgs is ${nix_go_version}, but ${min_version} or greater is required."
      exit 1
    fi

    echo "${OK} Go in nixpkgs is ${nix_go_version} (>= ${min_version})."
    return 0
  fi

  if command -v go >/dev/null 2>&1; then
    go_version=$(
      go version |
        awk '{print $3}' |
        sed 's/^go//'
    )

    if [ -n "$go_version" ] &&
       [ "$(printf '%s\n' "$min_version" "$go_version" |
         sort -V |
         head -n1)" = "$min_version" ]; then

      echo "${OK} Go is ${go_version} (>= ${min_version})."
      return 0
    fi

    echo "${ERROR} Go is ${go_version}, but ${min_version} or greater is required."
    exit 1
  fi

  echo "${ERROR} Unable to determine Go version. Please ensure Go ${min_version}+ is available."
  exit 1
}

nhl_ensure_required_packages() {
  local config="/etc/nixos/configuration.nix"
  local missing=()
  local cmd
  local pkg
  local fwupd_configured=false
  local fwupd_functional=false

  declare -A packages=(
    [git]="git"
    [lspci]="pciutils"
    [go]="go"
    [fwupdmgr]="fwupd"
  )

  echo "[ACTION] Checking required packages..."

  for cmd in "${!packages[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "[OK] $cmd is installed."
    else
      echo "[WARN] $cmd is not installed."
      missing+=("${packages[$cmd]}")
    fi
  done

  if grep -qE \
    'services\.fwupd\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;' \
    "$config" 2>/dev/null; then

    fwupd_configured=true
  fi

  if command -v fwupdmgr >/dev/null 2>&1; then
    echo "[ACTION] Testing fwupd daemon connectivity..."

    if sudo fwupdmgr get-devices >/dev/null 2>&1; then
      fwupd_functional=true
      echo "[OK] fwupdmgr can communicate with fwupd."
    else
      echo "[WARN] fwupdmgr could not communicate with fwupd."
    fi
  fi

  if [ "${#missing[@]}" -eq 0 ] &&
     [ "$fwupd_configured" = true ] &&
     [ "$fwupd_functional" = true ]; then

    echo "[OK] All required packages and fwupd are available."
    return 0
  fi

  echo
  echo "[WARN] Required packages/services are missing or not configured."

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "[INFO] Missing packages:"
    printf '  - %s\n' "${missing[@]}"
  fi

  if [ "$fwupd_configured" = false ]; then
    echo "  - services.fwupd.enable = true"
  fi

  if [ "$fwupd_functional" = false ] &&
     command -v fwupdmgr >/dev/null 2>&1; then
    echo "  - fwupd daemon connectivity"
  fi

  echo

  local choice=""

  choice=$(nhl_read_input \
    "Add/fix required packages and fwupd in NixOS, then rebuild? [Y/n/c=continue] " \
    "y")

  case "${choice,,}" in
    c|continue)
      echo "[NOTE] Continuing without fixing missing requirements."
      return 0
      ;;

    n|no)
      echo "[NOTE] Skipping required package/service setup."
      return 0
      ;;
  esac

  if [ ! -f "$config" ]; then
    echo "[ERROR] $config does not exist."
    return 1
  fi

  echo "[ACTION] Updating $config..."

  if [ "${#missing[@]}" -gt 0 ]; then
    if ! grep -q 'environment\.systemPackages' "$config"; then
      cat <<'EOF' | sudo tee -a "$config" >/dev/null

environment.systemPackages = with pkgs; [
];
EOF
    fi

    for pkg in "${missing[@]}"; do
      if ! grep -qE \
        "^[[:space:]]*${pkg}[[:space:]]*$" \
        "$config"; then

        local tmp=""
        local mode=""
        local owner=""
        local group=""

        tmp=$(mktemp "${TMPDIR:-/tmp}/nhl-package.XXXXXX") || {
          echo "[ERROR] Could not create temporary file for package insertion."
          return 1
        }

        mode=$(stat -c '%a' "$config" 2>/dev/null || echo 644)
        owner=$(stat -c '%u' "$config" 2>/dev/null || true)
        group=$(stat -c '%g' "$config" 2>/dev/null || true)

        if ! awk \
          -v new_pkg="$pkg" '
            /environment\.systemPackages = with pkgs; \[/ {
              print
              print "    " new_pkg
              next
            }
            { print }
          ' "$config" >"$tmp"; then

          rm -f "$tmp"
          echo "[ERROR] Failed to add package $pkg."
          return 1
        fi

        if [ -w "$config" ]; then
          if ! cat "$tmp" >"$config"; then
            rm -f "$tmp"
            echo "[ERROR] Failed to write $config."
            return 1
          fi

          chmod "$mode" "$config" 2>/dev/null || true
        else
          if ! sudo install -m "$mode" "$tmp" "$config"; then
            rm -f "$tmp"
            echo "[ERROR] sudo could not update $config."
            return 1
          fi

          if [ -n "$owner" ] &&
             [ -n "$group" ]; then
            sudo chown "${owner}:${group}" "$config" 2>/dev/null || true
          fi
        fi

        rm -f "$tmp"

        echo "[OK] Added $pkg."
      else
        echo "[NOTE] $pkg is already in the NixOS configuration."
      fi
    done
  fi

  if [ "$fwupd_configured" = false ]; then
    echo "[ACTION] Enabling fwupd service..."

    if grep -q 'services\.fwupd\.enable' "$config"; then
      nhl_sed_file \
        "$config" \
        -e 's/services\.fwupd\.enable[[:space:]]*=[[:space:]]*[^;]*;/services.fwupd.enable = true;/' || {
          echo "[ERROR] Failed to update services.fwupd.enable."
          return 1
        }
    else
      nhl_insert_option_before_closing_brace \
        "$config" \
        "services.fwupd.enable = true;" || {
          echo "[ERROR] Failed to insert services.fwupd.enable."
          return 1
        }
    fi

    echo "[OK] Added services.fwupd.enable = true."
  fi

  echo
  echo "[ACTION] Rebuilding NixOS before continuing..."

  if ! sudo nixos-rebuild switch; then
    echo "[ERROR] NixOS rebuild failed."
    return 1
  fi

  echo "[OK] NixOS rebuild completed."

  for cmd in "${!packages[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[ERROR] $cmd is still unavailable after the rebuild."
      return 1
    fi
  done

  echo "[ACTION] Verifying fwupd daemon connectivity..."

  if sudo fwupdmgr get-devices >/dev/null 2>&1; then
    echo "[OK] fwupdmgr can communicate with the fwupd daemon."
  else
    echo "[ERROR] fwupdmgr could not communicate with the fwupd daemon after the rebuild."
    echo "[ERROR] Check: sudo systemctl status fwupd.service"
    echo "[ERROR] Check: sudo journalctl -u fwupd.service -b --no-pager"
    return 1
  fi

  echo "[OK] All required packages and fwupd are installed and functional."
}

nhl_prompt_fingerprint() {
  # Args: $1 = hostName
  local hostName="$1"
  local cfg=""

  cfg=$(nhl_host_config_path "$hostName")

  local enable_fp
  local default_prompt="(y/N)"
  local default_value="n"

  if [ "${NHL_STATE_FINGERPRINT:-false}" = "true" ]; then
    default_prompt="(Y/n)"
    default_value="y"
  fi

  enable_fp=$(
    nhl_read_input \
      "Enable fingerprint login (fprintd) for ly/login? ${default_prompt}: " \
      "$default_value"
  )

  if echo "${enable_fp:-n}" | grep -qi '^y'; then
    if grep -q 'local\.security\.fingerprint\.enable' "$cfg"; then
      nhl_sed_file \
        "$cfg" \
        -e 's/local\.security\.fingerprint\.enable = [^;]*;/local.security.fingerprint.enable = true;/' ||
        true
    else
      nhl_insert_option_before_closing_brace \
        "$cfg" \
        "local.security.fingerprint.enable = true;"
    fi

    export NHL_ENABLE_FINGERPRINT=1
    echo "${OK} Fingerprint login enabled in host config."
  else
    if grep -q 'local\.security\.fingerprint\.enable' "$cfg"; then
      nhl_sed_file \
        "$cfg" \
        -e 's/local\.security\.fingerprint\.enable = [^;]*;/local.security.fingerprint.enable = false;/' ||
        true
    else
      nhl_insert_option_before_closing_brace \
        "$cfg" \
        "local.security.fingerprint.enable = false;"
    fi

    export NHL_ENABLE_FINGERPRINT=0
    echo "${NOTE} Fingerprint login left disabled."
  fi
}

nhl_prompt_vscode_confirm_sync() {
  # Args: $1 = hostName
  local hostName="$1"
  local vars=""

  vars=$(nhl_host_variables_path "$hostName")

  local default_prompt="(y/N)"
  local default_value="n"

  if [ "${NHL_STATE_VSCODE_CONFIRM_SYNC:-true}" = "false" ]; then
    default_prompt="(Y/n)"
    default_value="y"
  fi

  local always_sync

  always_sync=$(
    nhl_read_input \
      "Want VS Code to always sync when committing? ${default_prompt}: " \
      "$default_value"
  )

  if echo "${always_sync:-n}" | grep -qi '^y'; then
    if grep -q 'vscodeGitConfirmSync' "$vars"; then
      nhl_sed_file \
        "$vars" \
        -e 's/vscodeGitConfirmSync = [^;]*;/vscodeGitConfirmSync = false;/' ||
        true
    else
      nhl_insert_option_before_closing_brace \
        "$vars" \
        "vscodeGitConfirmSync = false; # false skips the VS Code sync confirmation prompt."
    fi

    export NHL_VSCODE_CONFIRM_SYNC=false
    echo "${OK} VS Code sync confirmation disabled."
  else
    if grep -q 'vscodeGitConfirmSync' "$vars"; then
      nhl_sed_file \
        "$vars" \
        -e 's/vscodeGitConfirmSync = [^;]*;/vscodeGitConfirmSync = true;/' ||
        true
    else
      nhl_insert_option_before_closing_brace \
        "$vars" \
        "vscodeGitConfirmSync = true; # true keeps the VS Code sync confirmation prompt."
    fi

    export NHL_VSCODE_CONFIRM_SYNC=true
    echo "${NOTE} VS Code sync confirmation kept enabled."
  fi
}

nhl_enroll_fingerprint() {
  # Args: $1 = username
  local userName="$1"

  if [ "${NHL_ENABLE_FINGERPRINT:-0}" != "1" ]; then
    return 0
  fi

  if nhl_is_noninteractive; then
    echo "${NOTE} Non-interactive mode detected; skipping fingerprint enrollment for now."
    return 0
  fi

  if ! command -v fprintd-enroll >/dev/null 2>&1; then
    echo "${WARN} fprintd-enroll not found yet. You can enroll later with: sudo fprintd-enroll ${userName}"
    return 0
  fi

  if ! nhl_yes_no \
    "Enroll fingerprint now for ${userName}? (Y/n): "; then

    echo "${NOTE} Skipping enrollment for now. Run later: sudo fprintd-enroll ${userName}"
    return 0
  fi

  echo "${INFO} Starting fingerprint enrollment for ${userName}..."

  sudo fprintd-enroll "$userName" || {
    echo "${WARN} Enrollment did not complete. You can retry later: sudo fprintd-enroll ${userName}"
    return 0
  }

  echo "${OK} Fingerprint enrollment completed."
}

nhl_prompt_firmware_updates() {
  # Firmware behavior:
  #
  # 1. User must explicitly request a firmware check.
  # 2. fwupd connectivity is verified.
  # 3. Metadata is refreshed.
  # 4. get-updates is queried.
  # 5. If there are no updates, return immediately.
  # 6. Only ask "Apply..." when actual updates are available.
  #
  # This avoids asking the user to apply updates after fwupdmgr has already
  # reported "No updatable devices".

  if ! nhl_yes_no \
    "Check firmware updates with fwupd before continuing? (y/N): "; then
    return 0
  fi

  if ! command -v fwupdmgr >/dev/null 2>&1; then
    echo "${WARN} fwupdmgr is not installed."
    echo "${NOTE} The installer will continue without firmware inspection."
    return 0
  fi

  echo "${INFO} Testing fwupd daemon connectivity..."

  if ! sudo fwupdmgr get-devices >/dev/null 2>&1; then
    echo "${WARN} fwupdmgr could not communicate with the fwupd daemon."
    echo "${NOTE} Firmware inspection cannot continue."
    return 0
  fi

  echo "${OK} fwupdmgr successfully connected to fwupd."

  echo "${INFO} Refreshing firmware metadata..."

  if ! sudo fwupdmgr refresh --force; then
    echo "${WARN} Firmware metadata refresh failed."
    echo "${NOTE} Continuing with currently available firmware metadata."
  fi

  echo "${INFO} Listing firmware devices..."
  sudo fwupdmgr get-devices || true

  echo "${INFO} Checking for available firmware updates..."

  local updates_output=""

  updates_output=$(
    sudo fwupdmgr get-updates 2>&1 ||
      true
  )

  printf "%s\n" "$updates_output"

  # fwupdmgr can report this in slightly different wording depending on
  # version/backend. Treat all of these as "nothing to install".
  if echo "$updates_output" |
    grep -qiE \
      'No updates available|No updatable devices|no available firmware updates'; then

    echo "${NOTE} No firmware updates are available; continuing without update prompt."
    return 0
  fi

  # Some fwupd versions print only "Devices with no available firmware
  # updates" when nothing can be updated. If there is no actual update
  # payload indication, do not ask to install.
  if ! echo "$updates_output" |
    grep -qiE \
      'Upgrade|Update|Downgrade|firmware.*available|available.*firmware|version.*->'; then

    echo "${NOTE} fwupd reported no actionable firmware update."
    return 0
  fi

  if nhl_yes_no \
    "Apply available firmware updates now? (y/N): "; then

    if sudo fwupdmgr update; then
      echo "${OK} Firmware update operation completed."
      echo "${NOTE} If firmware updates were installed, a reboot may be required."
    else
      echo "${ERROR} Firmware update operation failed."
      return 1
    fi
  else
    echo "${NOTE} Firmware updates were detected but not installed."
  fi
}

nhl_host_config_path() {
  # Args: $1 = hostName
  #
  # Generated host config is authoritative.
  #
  # There is intentionally NO fallback to hosts/default/config.nix.
  # The installer should never accidentally modify the permanent template
  # while working on a generated host.

  local hostName="$1"
  local cfg=".local-host/${hostName}/config.nix"

  if [ ! -f "$cfg" ]; then
    echo "[ERROR] Host configuration not found: $cfg" >&2
    return 1
  fi

  printf "%s\n" "$cfg"
}

nhl_host_variables_path() {
  # Args: $1 = hostName
  #
  # Generated host variables are authoritative.
  # No template fallback.

  local hostName="$1"
  local vars=".local-host/${hostName}/variables.nix"

  if [ ! -f "$vars" ]; then
    echo "[ERROR] Host variables configuration not found: $vars" >&2
    return 1
  fi

  printf "%s\n" "$vars"
}

nhl_host_hardware_path() {
  # Args: $1 = hostName
  #
  # Generated/installed hosts live under:
  #
  #   <repoRoot>/.local-host/<hostName>/hardware.nix
  #
  # hosts/default is the template only and is NEVER used as a fallback
  # for host-specific hardware detection.
  #
  # A missing hardware.nix is a hard error.
  #
  # A present hardware.nix which contains no LUKS mapping is NOT an error.
  # That is simply a non-LUKS machine.

  local hostName="$1"
  local repoRoot=""
  local hw=""

  repoRoot=$(nhl_repo_root) || {
    echo "[ERROR] Could not determine repository root." >&2
    return 1
  }

  hw="${repoRoot}/.local-host/${hostName}/hardware.nix"

  if [ ! -f "$hw" ]; then
    echo "[ERROR] Host hardware configuration not found: $hw" >&2
    echo "[ERROR] Refusing to fall back to hosts/default/hardware.nix." >&2
    return 1
  fi

  printf "%s\n" "$hw"
}

nhl_extract_luks_name_from_hardware() {
  # Args: $1 = hostName
  #
  # IMPORTANT:
  # No LUKS mapping is a valid result.
  #
  # Return codes:
  #   0 = LUKS mapping found
  #   1 = no LUKS mapping found OR hardware file unavailable
  #
  # Callers which need to distinguish those cases should first resolve
  # nhl_host_hardware_path successfully.

  local hostName="$1"
  local hw=""
  local name=""

  hw=$(nhl_host_hardware_path "$hostName") || return 1

  name=$(
    sed -n \
      's/^[[:space:]]*boot\.initrd\.luks\.devices\."\([^"]*\)"\.device[[:space:]]*=[[:space:]]*".*";/\1/p' \
      "$hw" |
      head -n1
  )

  if [ -n "$name" ]; then
    printf "%s\n" "$name"
    return 0
  fi

  return 1
}

nhl_extract_luks_device_from_hardware() {
  # Args: $1 = hostName
  #
  # No LUKS mapping is a normal non-LUKS result.
  # Do not print an error merely because the hardware file has no LUKS entry.

  local hostName="$1"
  local hw=""
  local dev=""

  hw=$(nhl_host_hardware_path "$hostName") || return 1

  dev=$(
    sed -n \
      's/^[[:space:]]*boot\.initrd\.luks\.devices\..*\.device[[:space:]]*=[[:space:]]*"\([^"]*\)";/\1/p' \
      "$hw" |
      head -n1
  )

  if [ -n "$dev" ]; then
    printf "%s\n" "$dev"
    return 0
  fi

  return 1
}

nhl_patch_host_for_tpm_unlock() {
  # Args: $1 = hostName, $2 = luksName
  local hostName="$1"
  local luksName="$2"
  local cfg=""
  local crypttabLine=""

  cfg=$(nhl_host_config_path "$hostName") || return 1

  [ -f "$cfg" ] || return 1
  [ -n "$luksName" ] || return 1

  nhl_sed_file \
    "$cfg" \
    -e '/systemd\.mask=dev-tpmrm0\.device/d' ||
    true

  if grep -q 'boot\.initrd\.systemd\.enable[[:space:]]*=' "$cfg"; then
    nhl_sed_file \
      "$cfg" \
      -e 's/boot\.initrd\.systemd\.enable[[:space:]]*=.*/boot.initrd.systemd.enable = true;/' ||
      true
  else
    nhl_insert_option_before_closing_brace \
      "$cfg" \
      "boot.initrd.systemd.enable = true;"
  fi

  if grep -q 'security\.tpm2\.enable[[:space:]]*=' "$cfg"; then
    nhl_sed_file \
      "$cfg" \
      -e 's/security\.tpm2\.enable[[:space:]]*=.*/security.tpm2.enable = true;/' ||
      true
  else
    nhl_insert_option_before_closing_brace \
      "$cfg" \
      "security.tpm2.enable = true;"
  fi

  crypttabLine="boot.initrd.luks.devices.\"${luksName}\".crypttabExtraOpts = [ \"tpm2-device=auto\" \"tpm2-pcrs=7\" ];"

  nhl_sed_file \
    "$cfg" \
    -e "/boot\.initrd\.luks\.devices\.\"${luksName//\//\\/}\"\.crypttabExtraOpts[[:space:]]*=/d" ||
    true

  nhl_insert_option_before_closing_brace \
    "$cfg" \
    "$crypttabLine" || return 1

  export NHL_ENABLE_TPM_LUKS_ENROLL=1
  export NHL_LUKS_NAME="$luksName"

  return 0
}

nhl_prompt_luks_tpm_setup() {
  # Args: $1 = hostName
  #
  # Behavior:
  #
  #   Missing hardware.nix:
  #       hard error
  #
  #   hardware.nix exists but contains no LUKS:
  #       valid, continue normally
  #
  #   hardware.nix contains LUKS:
  #       optionally perform TPM/recovery setup
  #
  # There is NEVER a hosts/default/hardware.nix fallback.

  local hostName="$1"
  local luksDevice=""
  local luksName=""
  local luksPassphrase=""
  local resolvedHardware=""

  export NHL_ENABLE_TPM_LUKS_ENROLL=0

  unset \
    NHL_LUKS_DEVICE \
    NHL_LUKS_NAME \
    NHL_RECOVERY_KEY \
    NHL_RECOVERY_KEY_SHA256 \
    NHL_RECOVERY_KEY_SHA512 \
    NHL_LUKS_CURRENT_PASSPHRASE

  # First and separately validate the hardware file itself.
  #
  # This is intentionally NOT hidden behind the LUKS extraction calls,
  # because "hardware file missing" and "hardware file has no LUKS" are
  # completely different situations.
  resolvedHardware=$(nhl_host_hardware_path "$hostName") || {
    echo "${ERROR} Host hardware configuration is required and could not be resolved."
    echo "${ERROR} No template fallback will be attempted."
    return 1
  }

  if nhl_is_noninteractive; then
    echo "${NOTE} Hardware configuration found: ${resolvedHardware}"
    echo "${NOTE} Non-interactive mode detected; skipping LUKS/TPM enrollment."
    return 0
  fi

  # Hardware file exists. Now inspect it.
  #
  # Failure here means simply "no LUKS mapping". It is NOT an error.
  luksDevice=$(nhl_extract_luks_device_from_hardware "$hostName" || true)
  luksName=$(nhl_extract_luks_name_from_hardware "$hostName" || true)

  if [ -z "$luksDevice" ] || [ -z "$luksName" ]; then
    echo "${NOTE} No LUKS device mapping found in host hardware config."
    echo "${NOTE} Hardware file: ${resolvedHardware}"
    echo "${NOTE} This machine appears to use no LUKS device."
    echo "${NOTE} Skipping TPM/LUKS enrollment."
    return 0
  fi

  echo "${INFO} LUKS device mapping detected:"
  echo "  Name:   ${luksName}"
  echo "  Device: ${luksDevice}"

  if ! sudo cryptsetup isLuks "$luksDevice" >/dev/null 2>&1; then
    echo "${WARN} Hardware configuration contains a LUKS mapping, but ${luksDevice} is not currently a valid LUKS device."
    echo "${NOTE} Skipping TPM unlock enrollment."
    return 0
  fi

  echo "${INFO} Valid LUKS device detected at ${luksDevice}."

  if ! nhl_yes_no \
    "Do you have your current LUKS passphrase available now? (y/N): "; then

    echo "${NOTE} LUKS passphrase not confirmed. Skipping TPM/recovery enrollment."
    return 0
  fi

  read -r -s -p \
    "Enter current LUKS passphrase (leave empty to skip TPM/recovery enrollment): " \
    luksPassphrase </dev/tty ||
    true

  printf "\n"

  if [ -z "$luksPassphrase" ]; then
    echo "${NOTE} No passphrase entered. Skipping TPM/recovery enrollment."
    return 0
  fi

  if ! nhl_yes_no \
    "Are u sure? This will modify LUKS keyslots on ${luksDevice}. (y/N): "; then

    echo "${NOTE} Confirmation declined. Skipping LUKS changes."
    return 0
  fi

  if ! nhl_yes_no \
    "Are u sure, again? TPM auto-unlock + recovery key setup will now be enforced. (y/N): "; then

    echo "${NOTE} Second confirmation declined. Skipping LUKS changes."
    return 0
  fi

  nhl_patch_host_for_tpm_unlock "$hostName" "$luksName" || {
    echo "${ERROR} Failed to patch host config for TPM unlock."
    return 1
  }

  export NHL_LUKS_DEVICE="$luksDevice"
  export NHL_LUKS_CURRENT_PASSPHRASE="$luksPassphrase"

  luksPassphrase=""

  echo "${OK} Host config patched for TPM-bound unlock on ${luksDevice}."
  echo "${NOTE} Enrollment will continue after nixos-rebuild switch."
}

nhl_generate_recovery_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi

  head -c 32 /dev/urandom |
    od -An -tx1 |
    tr -d ' \n'
}

nhl_run_luks_tpm_enrollment() {
  # Args: $1 = hostName
  local hostName="$1"
  local luksDevice="${NHL_LUKS_DEVICE:-}"
  local recoveryKey=""
  local sha256=""
  local sha512=""
  local currentPassphrase="${NHL_LUKS_CURRENT_PASSPHRASE:-}"
  local tmpKeyFile=""
  local hashFile=""
  local hashFile512=""

  if [ "${NHL_ENABLE_TPM_LUKS_ENROLL:-0}" != "1" ]; then
    return 0
  fi

  if [ -z "$luksDevice" ]; then
    luksDevice=$(nhl_extract_luks_device_from_hardware "$hostName" || true)
  fi

  if [ -z "$luksDevice" ]; then
    echo "${ERROR} TPM enrollment was requested but no LUKS device could be resolved."
    return 1
  fi

  if [ -z "$currentPassphrase" ]; then
    echo "${NOTE} No current LUKS passphrase available. Skipping TPM/recovery enrollment."
    return 0
  fi

  if ! sudo cryptsetup isLuks "$luksDevice"; then
    echo "${WARN} Target ${luksDevice} is not a LUKS device. Skipping enrollment."
    return 0
  fi

  if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
    echo "${ERROR} systemd-cryptenroll not found. Cannot enroll TPM unlock."
    return 1
  fi

  recoveryKey=$(nhl_generate_recovery_key)

  if [ -z "$recoveryKey" ]; then
    echo "${ERROR} Failed to generate recovery key."
    return 1
  fi

  tmpKeyFile=$(mktemp) || {
    echo "${ERROR} Could not create temporary recovery-key file."
    return 1
  }

  chmod 600 "$tmpKeyFile"
  printf "%s" "$recoveryKey" >"$tmpKeyFile"

  echo "${INFO} Adding generated recovery key to LUKS keyslots."

  if ! printf "%s" "$currentPassphrase" |
    sudo cryptsetup luksAddKey \
      "$luksDevice" \
      "$tmpKeyFile" \
      --key-file -; then

    rm -f "$tmpKeyFile"

    echo "${WARN} Could not authorize LUKS keyslot update (missing/wrong passphrase)."
    echo "${NOTE} Skipping TPM/recovery enrollment."
    return 0
  fi

  echo "${INFO} Enrolling TPM2 unlock (PCR7 binding) on ${luksDevice}."

  if ! sudo systemd-cryptenroll \
    "$luksDevice" \
    --tpm2-device=auto \
    --tpm2-pcrs=7; then

    rm -f "$tmpKeyFile"

    echo "${ERROR} TPM enrollment failed. Recovery key was added, but TPM unlock is not active."
    return 1
  fi

  rm -f "$tmpKeyFile"

  sha256=$(
    printf "%s" "$recoveryKey" |
      sha256sum |
      awk '{print $1}'
  )

  sha512=$(
    printf "%s" "$recoveryKey" |
      sha512sum |
      awk '{print $1}'
  )

  local recoveryDir=".local-host/$hostName"

  mkdir -p "$recoveryDir"

  hashFile="${recoveryDir}/.luks-recovery-key.sha256"
  hashFile512="${recoveryDir}/.luks-recovery-key.sha512"

  umask 077

  cat >"$hashFile" <<EOF
device=$luksDevice
sha256=$sha256
generated_at=$(date -Iseconds)
EOF

  cat >"$hashFile512" <<EOF
device=$luksDevice
sha512=$sha512
generated_at=$(date -Iseconds)
EOF

  chmod 600 "$hashFile" "$hashFile512" 2>/dev/null || true

  export NHL_RECOVERY_KEY="$recoveryKey"
  export NHL_RECOVERY_KEY_SHA256="$sha256"
  export NHL_RECOVERY_KEY_SHA512="$sha512"
  export NHL_LUKS_DEVICE="$luksDevice"

  unset NHL_LUKS_CURRENT_PASSPHRASE

  currentPassphrase=""
  recoveryKey=""

  echo "${OK} TPM + recovery-key enrollment completed for ${luksDevice}."
}

nhl_print_recovery_key_and_confirm() {
  local recoveryKey="${NHL_RECOVERY_KEY:-}"
  local sha256="${NHL_RECOVERY_KEY_SHA256:-}"
  local sha512="${NHL_RECOVERY_KEY_SHA512:-}"
  local luksDevice="${NHL_LUKS_DEVICE:-unknown}"

  if [ -z "$recoveryKey" ]; then
    return 0
  fi

  printf "%s\n" "-----"
  printf "%s\n" "[WARN] Recovery key generated for ${luksDevice}"
  printf "%s\n" "Recovery key (store offline now):"
  printf "%s\n" "${recoveryKey}"
  printf "%s\n" "SHA-256: ${sha256}"
  printf "%s\n" "SHA-512: ${sha512}"
  printf "%s\n" "Hash copies saved under .local-host/<hostname>/.luks-recovery-key.sha{256,512}"
  printf "%s\n" "-----"

  if ! nhl_yes_no "Are u sure you saved this recovery key? (y/N): "; then
    printf "%s\n" "${WARN} Please save it first. The key is shown again below:"
    printf "%s\n" "${recoveryKey}"
  fi

  until nhl_yes_no \
    "Are u sure, again, that your recovery key is safely stored? (y/N): "; do

    printf "%s\n" "${WARN} Recovery key still needs to be saved before reboot."
    printf "%s\n" "${recoveryKey}"
  done
}
