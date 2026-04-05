#!/usr/bin/env bash
# Common installer helpers for NixOS-Hyprland
# Sourced by install.sh and auto-install.sh

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

nhl_patch_flake_identity() {
  # Args: $1 = repo root, $2 = hostName, $3 = username
  local repoRoot="$1"
  local hostName="$2"
  local installUsername="$3"
  local flakeFile="${repoRoot}/flake.nix"

  [ -f "$flakeFile" ] || return 1

  sed -i -E '0,/(^\s*host\s*=\s*")([^"]*)(";)/s//\1'"$hostName"'\3/' "$flakeFile"
  sed -i -E '0,/(^\s*username\s*=\s*")([^"]*)(";)/s//\1'"$installUsername"'\3/' "$flakeFile"
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
  if [ "${NHL_NONINTERACTIVE:-0}" = "1" ] || [ "${INTUNE_MANAGED:-0}" = "1" ] || [ -n "${INTUNE_DEVICE_ID:-}" ] || [ ! -r /dev/tty ]; then
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
  # In managed/non-interactive runs, use a bootstrap account.
  if nhl_is_noninteractive; then
    printf "risiq-bootstrap\n"
  else
    printf "%s\n" "${USER}"
  fi
}

nhl_detect_host_serial() {
  local serial=""

  if [ -r /sys/class/dmi/id/product_serial ]; then
    serial=$(tr -d '[:space:]' </sys/class/dmi/id/product_serial 2>/dev/null || true)
  fi

  if [ -z "$serial" ] && [ -r /sys/devices/virtual/dmi/id/product_serial ]; then
    serial=$(tr -d '[:space:]' </sys/devices/virtual/dmi/id/product_serial 2>/dev/null || true)
  fi

  if [ -z "$serial" ] && [ -r /etc/machine-id ]; then
    serial=$(cut -c1-12 /etc/machine-id 2>/dev/null || true)
  fi

  printf "%s\n" "$serial"
}

nhl_sanitize_hostname() {
  local raw="$1"
  local sanitized=""

  sanitized=$(printf "%s" "$raw" | tr '[:space:]' '-' | tr -cd '[:alnum:]-')
  sanitized=$(printf "%s" "$sanitized" | sed 's/--*/-/g; s/^-//; s/-$//')
  sanitized="${sanitized:0:63}"
  if [ -z "$sanitized" ]; then
    sanitized="RISIQ-UNKNOWN"
  fi
  printf "%s\n" "$sanitized"
}

nhl_derive_hostname() {
  # Args: $1 = optional prefix (default: RISIQ)
  local prefix="${1:-RISIQ}"
  local serial=""
  local serial_clean=""
  local hostName=""

  serial=$(nhl_detect_host_serial)
  # Keep alphanumeric only for hostname safety.
  serial_clean=$(echo "$serial" | tr -cd '[:alnum:]')
  if [ -z "$serial_clean" ]; then
    serial_clean="UNKNOWN"
  fi

  hostName="${prefix}-${serial_clean}"
  # Linux hostname max is 63 chars.
  hostName=$(nhl_sanitize_hostname "$hostName")

  printf "%s\n" "$hostName"
}

nhl_prompt_hostname() {
  local default_prefix="${1:-RISIQ}"
  local default_mode="${NHL_STATE_HOSTNAME_MODE:-prefix-serial}"
  local serial=""
  local serial_clean=""
  local mode_prompt="[p]refix+serial / [c]ustom name"
  local mode_default="p"
  local mode=""
  local prefix=""
  local custom=""

  serial=$(nhl_detect_host_serial)
  serial_clean=$(printf "%s" "$serial" | tr -cd '[:alnum:]')
  if [ -z "$serial_clean" ]; then
    serial_clean="UNKNOWN"
  fi

  if [ "$default_mode" = "custom" ]; then
    mode_default="c"
  fi

  mode=$(nhl_read_input "Choose hostname style ${mode_prompt}: [${mode_default}] " "$mode_default")
  if printf "%s" "$mode" | grep -qi '^c'; then
    custom=$(nhl_read_input "Enter the exact hostname to use (no serial will be appended): " "${NHL_STATE_HOSTNAME_VALUE:-}")
    export NHL_SELECTED_HOSTNAME_MODE="custom"
    export NHL_SELECTED_HOSTNAME_VALUE="$(nhl_sanitize_hostname "$custom")"
    printf "%s\n" "${NHL_SELECTED_HOSTNAME_VALUE}"
    return 0
  fi

  prefix=$(nhl_read_input "Enter hostname prefix to combine with this device serial (${serial_clean}): " "${NHL_STATE_HOSTNAME_PREFIX:-$default_prefix}")
  export NHL_SELECTED_HOSTNAME_MODE="prefix-serial"
  export NHL_SELECTED_HOSTNAME_PREFIX="$(nhl_sanitize_hostname "$prefix")"
  export NHL_SELECTED_HOSTNAME_VALUE="$(nhl_derive_hostname "${NHL_SELECTED_HOSTNAME_PREFIX}")"
  printf "%s\n" "${NHL_SELECTED_HOSTNAME_VALUE}"
}

nhl_preflight_install_repo() {
  local repoRoot="${1:-$(pwd)}"
  local missing=0

  for path in flake.nix install.sh auto-install.sh hosts/default/config.nix hosts/default/variables.nix scripts/lib/install-common.sh; do
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

nhl_is_enrolled_device() {
  # Args: $1 = hostName
  local hostName="$1"
  local marker="./hosts/$hostName/.nhl-enrolled"
  local mid=""

  if [ ! -f "$marker" ]; then
    return 1
  fi

  if [ -r /etc/machine-id ]; then
    mid=$(cat /etc/machine-id 2>/dev/null || true)
  fi

  # If no machine-id available, treat marker presence as enrolled.
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
  local marker="./hosts/$hostName/.nhl-enrolled"
  local mid=""
  local serial=""

  if [ -r /etc/machine-id ]; then
    mid=$(cat /etc/machine-id 2>/dev/null || true)
  fi
  if [ -r /sys/class/dmi/id/product_serial ]; then
    serial=$(tr -d '[:space:]' </sys/class/dmi/id/product_serial 2>/dev/null || true)
  fi

  mkdir -p "./hosts/$hostName"
  cat >"$marker" <<EOF
machine_id=$mid
serial=$serial
enrolled_at=$(date -Iseconds)
EOF
}

nhl_state_file() {
  # Args: $1 = hostName
  local hostName="$1"
  printf "./hosts/%s/.installer-state.json\n" "$hostName"
}

nhl_load_installer_state() {
  # Args: $1 = hostName
  local hostName="$1"
  local stateFile
  stateFile=$(nhl_state_file "$hostName")

  unset NHL_STATE_GPU_PROFILE NHL_STATE_KEYBOARD_LAYOUT NHL_STATE_TIMEZONE NHL_STATE_CONSOLE_KEYMAP NHL_STATE_FINGERPRINT NHL_STATE_VSCODE_CONFIRM_SYNC NHL_STATE_HOSTNAME_MODE NHL_STATE_HOSTNAME_PREFIX NHL_STATE_HOSTNAME_VALUE

  if [ ! -f "$stateFile" ]; then
    return 1
  fi

  NHL_STATE_GPU_PROFILE=$(sed -n 's/.*"gpu_profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_KEYBOARD_LAYOUT=$(sed -n 's/.*"keyboard_layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_TIMEZONE=$(sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_CONSOLE_KEYMAP=$(sed -n 's/.*"console_keymap"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_FINGERPRINT=$(sed -n 's/.*"fingerprint_enabled"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_VSCODE_CONFIRM_SYNC=$(sed -n 's/.*"vscode_confirm_sync"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_HOSTNAME_MODE=$(sed -n 's/.*"hostname_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_HOSTNAME_PREFIX=$(sed -n 's/.*"hostname_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)
  NHL_STATE_HOSTNAME_VALUE=$(sed -n 's/.*"hostname_value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stateFile" | head -n1)

  export NHL_STATE_GPU_PROFILE NHL_STATE_KEYBOARD_LAYOUT NHL_STATE_TIMEZONE NHL_STATE_CONSOLE_KEYMAP NHL_STATE_FINGERPRINT NHL_STATE_VSCODE_CONFIRM_SYNC NHL_STATE_HOSTNAME_MODE NHL_STATE_HOSTNAME_PREFIX NHL_STATE_HOSTNAME_VALUE
  return 0
}

nhl_save_installer_state() {
  # Args: $1 hostName, $2 keyboard, $3 timezone, $4 console keymap, $5 fingerprint(0/1), $6 gpu profile, $7 vscode confirm sync(true/false), $8 hostname mode, $9 hostname prefix, $10 hostname value
  local hostName="$1"
  local keyboardLayout="$2"
  local timeZone="$3"
  local consoleKeyMap="$4"
  local fingerprintEnabled="$5"
  local gpuProfile="$6"
  local vscodeConfirmSync="${7:-true}"
  local hostnameMode="${8:-prefix-serial}"
  local hostnamePrefix="${9:-RISIQ}"
  local hostnameValue="${10:-$hostName}"
  local stateFile
  local fpJson="false"

  stateFile=$(nhl_state_file "$hostName")
  mkdir -p "./hosts/$hostName"

  if [ "$fingerprintEnabled" = "1" ] || [ "$fingerprintEnabled" = "true" ]; then
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
  local cfg="./hosts/$hostName/config.nix"
  [ -f "$cfg" ] || cfg="./hosts/default/config.nix"

  local has_vm=false has_nvidia=false has_amd=false has_intel=false

  if hostnamectl | grep -q 'Chassis: vm'; then
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

  # Decide detected profile
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

  # Confirm or manually choose profile
  local profile="$detected"
  if [ -n "$detected" ]; then
    if ! nhl_yes_no "Detected GPU profile: ${detected}. Use this? (Y/n): "; then
      profile=""
    fi
  fi
  if [ -z "$profile" ]; then
    local default_profile="${NHL_STATE_GPU_PROFILE:-amd}"
    profile=$(nhl_read_input "Enter your GPU profile (amd|intel|nvidia|nvidia-laptop|vm): [${default_profile}] " "$default_profile")
  fi

  # Reset toggles
  sed -i 's/drivers\.amdgpu\.enable = [^;]*;/drivers.amdgpu.enable = false;/' "$cfg" || true
  sed -i 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = false;/' "$cfg" || true
  sed -i 's/drivers\.nvidia\.enable = [^;]*;/drivers.nvidia.enable = false;/' "$cfg" || true
  sed -i 's/drivers\.nvidia-prime\.enable = [^;]*;/drivers.nvidia-prime.enable = false;/' "$cfg" || true
  sed -i 's/vm\.guest-services\.enable = [^;]*;/vm.guest-services.enable = false;/' "$cfg" || true

  # Apply selected profile
  case "$profile" in
    vm)
      sed -i 's/vm\.guest-services\.enable = [^;]*;/vm.guest-services.enable = true;/' "$cfg" || true
      ;;
    nvidia-laptop)
      sed -i 's/drivers\.nvidia-prime\.enable = [^;]*;/drivers.nvidia-prime.enable = true;/' "$cfg" || true
      sed -i 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = true;/' "$cfg" || true
      ;;
    nvidia)
      sed -i 's/drivers\.nvidia\.enable = [^;]*;/drivers.nvidia.enable = true;/' "$cfg" || true
      ;;
    amd)
      sed -i 's/drivers\.amdgpu\.enable = [^;]*;/drivers.amdgpu.enable = true;/' "$cfg" || true
      ;;
    intel)
      sed -i 's/drivers\.intel\.enable = [^;]*;/drivers.intel.enable = true;/' "$cfg" || true
      ;;
    *)
      # Fallback: do nothing if unknown
      ;;
  esac

  export NHL_GPU_PROFILE="$profile"
}

nhl_insert_option_before_closing_brace() {
  # Args: $1 = file, $2 = full option line (including trailing ;)
  local file="$1"
  local line="$2"
  if [ -f "$file" ] && tail -n 1 "$file" | grep -q '^[[:space:]]*}[[:space:]]*$'; then
    sed -i '$i\  '"$line" "$file" || true
  else
    printf '\n  %s\n' "$line" >> "$file"
  fi
}

nhl_lookup_timezone_from_city() {
  # Args: $1 = city
  local city="$1"
  local encoded=""
  local resp=""
  local tz=""

  if [ -z "$city" ] || ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  # Minimal URL encoding for common city input.
  encoded=$(printf "%s" "$city" | sed -e 's/%/%25/g' -e 's/ /%20/g')
  resp=$(curl -fsSL --max-time 10 "https://geocoding-api.open-meteo.com/v1/search?name=${encoded}&count=1&language=en&format=json" 2>/dev/null || true)
  tz=$(echo "$resp" | tr -d '\n' | sed -n 's/.*"timezone":"\([^"]*\)".*/\1/p' | head -n1)

  if [ -n "$tz" ] && echo "$tz" | grep -q '/'; then
    printf "%s\n" "$tz"
    return 0
  fi

  return 1
}

nhl_detect_timezone_auto() {
  # Try local system timezone first, then IP-based lookup.
  local tz=""

  if command -v timedatectl >/dev/null 2>&1; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    if [ -n "$tz" ] && [ "$tz" != "n/a" ] && [ "$tz" != "UTC" ] && echo "$tz" | grep -q '/'; then
      printf "%s\n" "$tz"
      return 0
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    tz=$(curl -fsSL --max-time 8 https://ipapi.co/timezone 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$tz" ] && echo "$tz" | grep -q '/'; then
      printf "%s\n" "$tz"
      return 0
    fi
  fi

  return 1
}

nhl_prompt_timezone_console() {
  # Args: $1 = hostName, $2 = defaultKeyboardLayout
  local hostName="$1"
  local defKb="${2:-us}"
  local cfg="./hosts/$hostName/config.nix"
  [ -f "$cfg" ] || cfg="./hosts/default/config.nix"

  local timeZone=""
  local city=""
  local manualTz=""

  if [ -n "${NHL_STATE_TIMEZONE:-}" ]; then
    timeZone="$NHL_STATE_TIMEZONE"
    echo "${OK} Using saved timezone from previous installer run: ${timeZone}"
  elif timeZone=$(nhl_detect_timezone_auto); then
    echo "${OK} Detected timezone automatically: ${timeZone}"
  else
    city=$(nhl_read_input "Could not auto-detect timezone. Enter your current city (e.g. Mannheim): " "")
    if [ -n "$city" ]; then
      timeZone=$(nhl_lookup_timezone_from_city "$city" || true)
      if [ -n "$timeZone" ]; then
        echo "${OK} Mapped city '${city}' to timezone: ${timeZone}"
      fi
    fi
  fi

  if [ -z "$timeZone" ]; then
    manualTz=$(nhl_read_input "Enter your timezone manually (e.g. Europe/Berlin), or leave blank for automatic service: [auto] " "")
    timeZone="$manualTz"
  fi

  if [ -n "$timeZone" ]; then
    # Set explicit timezone and disable automatic
    if grep -q 'time\.timeZone' "$cfg"; then
      sed -i "s|time\.timeZone = \".*\";|time.timeZone = \"$timeZone\";|" "$cfg" || true
    else
      nhl_insert_option_before_closing_brace "$cfg" "time.timeZone = \"$timeZone\";"
    fi
    if grep -q 'services\.automatic-timezoned\.enable' "$cfg"; then
      sed -i 's/services\.automatic-timezoned\.enable = [^;]*/services.automatic-timezoned.enable = false/' "$cfg" || true
    else
      nhl_insert_option_before_closing_brace "$cfg" "services.automatic-timezoned.enable = false;"
    fi
  else
    # Prefer automatic time zone if still unknown
    if grep -q 'services\.automatic-timezoned\.enable' "$cfg"; then
      sed -i 's/services\.automatic-timezoned\.enable = [^;]*/services.automatic-timezoned.enable = true/' "$cfg" || true
    else
      nhl_insert_option_before_closing_brace "$cfg" "services.automatic-timezoned.enable = true;"
    fi
    # Remove explicit time.timeZone if present
    sed -i '/time\.timeZone[[:space:]]*=/{d}' "$cfg" || true
  fi

  # Console keymap follows chosen keyboard layout by default.
  local consoleKeyMap="${NHL_STATE_CONSOLE_KEYMAP:-$defKb}"
  # Replace any existing console.keyMap assignment
  if grep -q 'console\.keyMap' "$cfg"; then
    sed -i "s|console\.keyMap = \".*\";|console.keyMap = \"$consoleKeyMap\";|" "$cfg" || true
  else
    # Fallback: append a console.keyMap line near the end
    printf '\n  console.keyMap = "%s";\n' "$consoleKeyMap" >> "$cfg"
  fi

  export NHL_SELECTED_TIMEZONE="$timeZone"
  export NHL_SELECTED_CONSOLE_KEYMAP="$consoleKeyMap"
}

nhl_check_go_version() {
  local min_version="1.25.5"
  local nix_go_version=""
  local go_version=""

  if command -v nix >/dev/null 2>&1; then
    nix_go_version=$(NIX_CONFIG="experimental-features = nix-command flakes" nix eval --raw "nixpkgs#go.version" 2>/dev/null || true)
  fi

  if [ -n "$nix_go_version" ]; then
    if [ "$(printf '%s\n' "$min_version" "$nix_go_version" | sort -V | head -n1)" != "$min_version" ]; then
      echo "${ERROR} Go in nixpkgs is ${nix_go_version}, but ${min_version} or greater is required."
      exit 1
    fi
    echo "${OK} Go in nixpkgs is ${nix_go_version} (>= ${min_version})."
    return 0
  fi

  if command -v go >/dev/null 2>&1; then
    go_version=$(go version | awk '{print $3}' | sed 's/^go//')
    if [ -n "$go_version" ] && [ "$(printf '%s\n' "$min_version" "$go_version" | sort -V | head -n1)" = "$min_version" ]; then
      echo "${OK} Go is ${go_version} (>= ${min_version})."
      return 0
    fi
    echo "${ERROR} Go is ${go_version}, but ${min_version} or greater is required."
    exit 1
  fi

  echo "${ERROR} Unable to determine Go version. Please ensure Go ${min_version}+ is available."
  exit 1
}

nhl_prompt_fingerprint() {
  # Args: $1 = hostName
  local hostName="$1"
  local cfg="./hosts/$hostName/config.nix"
  [ -f "$cfg" ] || cfg="./hosts/default/config.nix"

  local enable_fp
  local default_prompt="(y/N)"
  local default_value="n"
  if [ "${NHL_STATE_FINGERPRINT:-false}" = "true" ]; then
    default_prompt="(Y/n)"
    default_value="y"
  fi

  enable_fp=$(nhl_read_input "Enable fingerprint login (fprintd) for ly/login? ${default_prompt}: " "$default_value")

  if echo "${enable_fp:-n}" | grep -qi '^y'; then
    if grep -q 'local\.security\.fingerprint\.enable' "$cfg"; then
      sed -i 's/local\.security\.fingerprint\.enable = [^;]*;/local.security.fingerprint.enable = true;/' "$cfg" || true
    else
      printf '\n  local.security.fingerprint.enable = true;\n' >> "$cfg"
    fi
    export NHL_ENABLE_FINGERPRINT=1
    echo "${OK} Fingerprint login enabled in host config."
  else
    if grep -q 'local\.security\.fingerprint\.enable' "$cfg"; then
      sed -i 's/local\.security\.fingerprint\.enable = [^;]*;/local.security.fingerprint.enable = false;/' "$cfg" || true
    else
      printf '\n  local.security.fingerprint.enable = false;\n' >> "$cfg"
    fi
    export NHL_ENABLE_FINGERPRINT=0
    echo "${NOTE} Fingerprint login left disabled."
  fi
}

nhl_prompt_vscode_confirm_sync() {
  # Args: $1 = hostName
  local hostName="$1"
  local vars="./hosts/$hostName/variables.nix"
  [ -f "$vars" ] || vars="./hosts/default/variables.nix"

  local default_prompt="(y/N)"
  local default_value="n"
  if [ "${NHL_STATE_VSCODE_CONFIRM_SYNC:-true}" = "false" ]; then
    default_prompt="(Y/n)"
    default_value="y"
  fi

  local always_sync
  always_sync=$(nhl_read_input "Want VS Code to always sync when committing? ${default_prompt}: " "$default_value")

  if echo "${always_sync:-n}" | grep -qi '^y'; then
    if grep -q 'vscodeGitConfirmSync' "$vars"; then
      sed -i 's/vscodeGitConfirmSync = [^;]*;/vscodeGitConfirmSync = false;/' "$vars" || true
    else
      printf '\n  vscodeGitConfirmSync = false; # false skips the VS Code sync confirmation prompt.\n' >> "$vars"
    fi
    export NHL_VSCODE_CONFIRM_SYNC=false
    echo "${OK} VS Code sync confirmation disabled."
  else
    if grep -q 'vscodeGitConfirmSync' "$vars"; then
      sed -i 's/vscodeGitConfirmSync = [^;]*;/vscodeGitConfirmSync = true;/' "$vars" || true
    else
      printf '\n  vscodeGitConfirmSync = true; # true keeps the VS Code sync confirmation prompt.\n' >> "$vars"
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

  if ! nhl_yes_no "Enroll fingerprint now for ${userName}? (Y/n): "; then
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
  # Optional pre-install firmware inspection/update helper (safe no-op if fwupd is unavailable).
  if ! nhl_yes_no "Check firmware updates with fwupd before continuing? (y/N): "; then
    return 0
  fi

  if ! command -v fwupdmgr >/dev/null 2>&1; then
    echo "${WARN} fwupdmgr is not installed in this environment."
    echo "${NOTE} You can run later after install: sudo fwupdmgr refresh --force && sudo fwupdmgr get-updates"
    return 0
  fi

  echo "${INFO} Refreshing firmware metadata..."
  sudo fwupdmgr refresh --force || true

  echo "${INFO} Listing firmware devices..."
  sudo fwupdmgr get-devices || true

  echo "${INFO} Checking for available firmware updates..."
  local updates_output=""
  updates_output=$(sudo fwupdmgr get-updates 2>&1 || true)
  printf "%s\n" "$updates_output"

  if echo "$updates_output" | grep -qi "No updates available"; then
    echo "${NOTE} No firmware updates available; continuing without update prompt."
    return 0
  fi

  if nhl_yes_no "Apply available firmware updates now? (y/N): "; then
    sudo fwupdmgr update || true
    echo "${NOTE} If firmware updates were installed, a reboot may be required."
  fi
}

nhl_host_config_path() {
  # Args: $1 = hostName
  local hostName="$1"
  local cfg="./hosts/$hostName/config.nix"
  if [ ! -f "$cfg" ]; then
    cfg="./hosts/default/config.nix"
  fi
  printf "%s\n" "$cfg"
}

nhl_host_hardware_path() {
  # Args: $1 = hostName
  local hostName="$1"
  local hw="./hosts/$hostName/hardware.nix"
  if [ ! -f "$hw" ]; then
    hw="./hosts/default/hardware.nix"
  fi
  printf "%s\n" "$hw"
}

nhl_extract_luks_name_from_hardware() {
  # Args: $1 = hostName
  local hostName="$1"
  local hw=""
  local name=""

  hw=$(nhl_host_hardware_path "$hostName")
  [ -f "$hw" ] || return 1

  name=$(sed -n 's/^[[:space:]]*boot\.initrd\.luks\.devices\."\([^"]*\)"\.device[[:space:]]*=[[:space:]]*".*";/\1/p' "$hw" | head -n1)
  if [ -n "$name" ]; then
    printf "%s\n" "$name"
    return 0
  fi

  return 1
}

nhl_extract_luks_device_from_hardware() {
  # Args: $1 = hostName
  local hostName="$1"
  local hw=""
  local dev=""

  hw=$(nhl_host_hardware_path "$hostName")
  [ -f "$hw" ] || return 1

  dev=$(sed -n 's/^[[:space:]]*boot\.initrd\.luks\.devices\..*\.device[[:space:]]*=[[:space:]]*"\([^"]*\)";/\1/p' "$hw" | head -n1)
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

  cfg=$(nhl_host_config_path "$hostName")
  [ -f "$cfg" ] || return 1
  [ -n "$luksName" ] || return 1

  # Remove TPM mask if present, otherwise TPM-based unlock cannot work.
  sed -i '/systemd\.mask=dev-tpmrm0\.device/d' "$cfg" || true

  if grep -q 'boot\.initrd\.systemd\.enable[[:space:]]*=' "$cfg"; then
    sed -i 's/boot\.initrd\.systemd\.enable[[:space:]]*=.*/boot.initrd.systemd.enable = true;/' "$cfg" || true
  else
    nhl_insert_option_before_closing_brace "$cfg" "boot.initrd.systemd.enable = true;"
  fi

  if grep -q 'security\.tpm2\.enable[[:space:]]*=' "$cfg"; then
    sed -i 's/security\.tpm2\.enable[[:space:]]*=.*/security.tpm2.enable = true;/' "$cfg" || true
  else
    nhl_insert_option_before_closing_brace "$cfg" "security.tpm2.enable = true;"
  fi

  crypttabLine="boot.initrd.luks.devices.\"${luksName}\".crypttabExtraOpts = [ \"tpm2-device=auto\" \"tpm2-pcrs=7\" ];"
  sed -i "/boot\.initrd\.luks\.devices\.\"${luksName//\//\\/}\"\.crypttabExtraOpts[[:space:]]*=/d" "$cfg" || true
  nhl_insert_option_before_closing_brace "$cfg" "$crypttabLine"

  export NHL_ENABLE_TPM_LUKS_ENROLL=1
  export NHL_LUKS_NAME="$luksName"
}

nhl_prompt_luks_tpm_setup() {
  # Args: $1 = hostName
  local hostName="$1"
  local luksDevice=""
  local luksName=""
  local luksPassphrase=""

  export NHL_ENABLE_TPM_LUKS_ENROLL=0
  unset NHL_LUKS_DEVICE NHL_LUKS_NAME NHL_RECOVERY_KEY NHL_RECOVERY_KEY_SHA256 NHL_RECOVERY_KEY_SHA512 NHL_LUKS_CURRENT_PASSPHRASE

  if nhl_is_noninteractive; then
    echo "${ERROR} Non-interactive mode detected. Mandatory LUKS+TPM enrollment requires interactive confirmation."
    return 1
  fi

  luksDevice=$(nhl_extract_luks_device_from_hardware "$hostName" || true)
  luksName=$(nhl_extract_luks_name_from_hardware "$hostName" || true)

  if [ -z "$luksDevice" ] || [ -z "$luksName" ]; then
    echo "${WARN} No LUKS root mapping was found in host hardware config."
    echo "${NOTE} Skipping TPM unlock enrollment. Disk encryption must be provisioned at install/partitioning time."
    return 0
  fi

  if ! sudo cryptsetup isLuks "$luksDevice" >/dev/null 2>&1; then
    echo "${WARN} LUKS mapping exists but ${luksDevice} is not a valid LUKS device."
    echo "${NOTE} Skipping TPM unlock enrollment to avoid installer errors on non-encrypted systems."
    return 0
  fi

  echo "${INFO} LUKS device detected at ${luksDevice}. Mandatory BitLocker-style setup is enabled for this installer run."

  if ! nhl_yes_no "Are u sure you have your current LUKS passphrase available now? (y/N): "; then
    echo "${ERROR} Current LUKS passphrase is required to authorize keyslot changes."
    return 1
  fi

  read -r -s -p "Enter current LUKS passphrase (leave empty to skip TPM/recovery enrollment): " luksPassphrase </dev/tty || true
  printf "\n"
  if [ -z "$luksPassphrase" ]; then
    echo "${NOTE} No passphrase entered. Skipping TPM/recovery enrollment without error."
    return 0
  fi

  if ! nhl_yes_no "Are u sure? This will modify LUKS keyslots on ${luksDevice}. (y/N): "; then
    echo "${ERROR} Confirmation declined. Stopping installer to avoid partial security setup."
    return 1
  fi

  if ! nhl_yes_no "Are u sure, again? TPM auto-unlock + recovery key setup will now be enforced. (y/N): "; then
    echo "${ERROR} Second confirmation declined. Stopping installer."
    return 1
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

  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
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
    echo "${ERROR} Could not resolve LUKS device for TPM enrollment."
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

  tmpKeyFile=$(mktemp)
  chmod 600 "$tmpKeyFile"
  printf "%s" "$recoveryKey" >"$tmpKeyFile"

  echo "${INFO} Adding generated recovery key to LUKS keyslots."
  if ! printf "%s" "$currentPassphrase" | sudo cryptsetup luksAddKey "$luksDevice" "$tmpKeyFile" --key-file -; then
    rm -f "$tmpKeyFile"
    echo "${WARN} Could not authorize LUKS keyslot update (missing/wrong passphrase). Skipping TPM/recovery enrollment."
    return 0
  fi

  echo "${INFO} Enrolling TPM2 unlock (PCR7 binding) on ${luksDevice}."
  if ! sudo systemd-cryptenroll "$luksDevice" --tpm2-device=auto --tpm2-pcrs=7; then
    rm -f "$tmpKeyFile"
    echo "${ERROR} TPM enrollment failed. Recovery key was added, but TPM unlock is not active."
    return 1
  fi

  rm -f "$tmpKeyFile"

  sha256=$(printf "%s" "$recoveryKey" | sha256sum | awk '{print $1}')
  sha512=$(printf "%s" "$recoveryKey" | sha512sum | awk '{print $1}')

  hashFile="./hosts/$hostName/.luks-recovery-key.sha256"
  hashFile512="./hosts/$hostName/.luks-recovery-key.sha512"
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
  printf "%s\n" "Hash copies saved under hosts/<hostname>/.luks-recovery-key.sha{256,512}"
  printf "%s\n" "-----"

  if ! nhl_yes_no "Are u sure you saved this recovery key? (y/N): "; then
    printf "%s\n" "${WARN} Please save it first. The key is shown again below:"
    printf "%s\n" "${recoveryKey}"
  fi

  until nhl_yes_no "Are u sure, again, that your recovery key is safely stored? (y/N): "; do
    printf "%s\n" "${WARN} Recovery key still needs to be saved before reboot."
    printf "%s\n" "${recoveryKey}"
  done
}
