# Project source: https://github.com/LinuxBeginnings/NixOS-Hyprland

#!/usr/bin/env bash
clear

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NHL_REPO_ROOT="$SCRIPT_DIR"

printf "\n%.0s" {1..2}
echo -e "\e[35m
	╦╔═┌─┐┌─┐╦    ╦ ╦┬ ┬┌─┐┬─┐┬  ┌─┐┌┐┌┌┬┐
	╠╩╗│ ││ │║    ╠═╣└┬┘├─┘├┬┘│  ├─┤│││ ││ 2025
	╩ ╩└─┘└─┘╩═╝  ╩ ╩ ┴ ┴  ┴└─┴─┘┴ ┴┘└┘─┴┘
\e[0m"
printf "\n%.0s" {1..1}

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

set -e

# ---------------------------------------------------------------------------
# Load shared installer functions.
# ---------------------------------------------------------------------------

if [ -f "${SCRIPT_DIR}/scripts/lib/install-common.sh" ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/scripts/lib/install-common.sh"
else
    echo "${ERROR} Missing scripts/lib/install-common.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify this is NixOS.
# ---------------------------------------------------------------------------

if grep -qi nixos /etc/os-release; then
    echo "${OK} Verified this is NixOS."
    echo "-----"
else
    echo "${ERROR} This is not NixOS or the distribution information is not available."
    exit 1
fi

# ---------------------------------------------------------------------------
# Required packages.
# ---------------------------------------------------------------------------

nhl_ensure_required_packages

# ---------------------------------------------------------------------------
# Repository.
# ---------------------------------------------------------------------------

echo "$NOTE Using the current installer repository"

cd "$NHL_REPO_ROOT" || {
    echo "${ERROR} Unable to enter repository: ${NHL_REPO_ROOT}"
    exit 1
}

echo "$NOTE Repository: $NHL_REPO_ROOT"
echo "-----"

if type nhl_preflight_install_repo >/dev/null 2>&1; then
    nhl_preflight_install_repo "${NHL_REPO_ROOT}" || exit 1
fi

printf "\n%.0s" {1..2}

echo "-----"
printf "\n%.0s" {1..1}

echo "$NOTE Default options are in brackets []"
echo "$NOTE Just press ${MAGENTA}ENTER${RESET} to select the default"

sleep 1

echo "-----"

# ===========================================================================
# HOSTNAME
# ===========================================================================

if type nhl_prompt_hostname >/dev/null 2>&1; then
    hostName=$(nhl_prompt_hostname "NixOS")
elif type nhl_derive_hostname >/dev/null 2>&1; then
    hostName=$(nhl_derive_hostname "NixOS")
else
    hostName="UNKNOWN-HOST"
fi

if [ -z "$hostName" ] || [ "$hostName" = "UNKNOWN-HOST" ]; then
    echo "${ERROR} Unable to determine hostname."
    exit 1
fi

echo "$NOTE Selected hostname: $hostName"
echo "-----"

# ===========================================================================
# MACHINE-LOCAL HOST PATHS
# ===========================================================================

localHostRoot="$NHL_REPO_ROOT/.local-host"
hostDir="$localHostRoot/$hostName"

export NHL_LOCAL_HOST_ROOT="$localHostRoot"
export NHL_HOSTNAME="$hostName"
export NHL_HOST_DIR="$hostDir"

echo "$NOTE Machine-local host root:"
echo "    $localHostRoot"

echo "$NOTE Machine-local host directory:"
echo "    $hostDir"

echo "-----"

# ===========================================================================
# ENSURE MACHINE-LOCAL ROOT EXISTS
# ===========================================================================

if [ ! -d "$localHostRoot" ]; then
    echo "$NOTE Creating machine-local host root..."

    mkdir -p "$localHostRoot"

    echo "$OK Created:"
    echo "    $localHostRoot"
fi

# ===========================================================================
# ENSURE CURRENT MACHINE HOST DIRECTORY EXISTS
# ===========================================================================

if [ -d "$hostDir" ]; then

    echo "$NOTE Local host directory already exists:"
    echo "    $hostDir"

    echo "$NOTE Preserving existing machine-specific files."

else

    echo "$NOTE Creating local host directory:"
    echo "    $hostDir"

    mkdir -p "$hostDir"

    echo "$OK Created:"
    echo "    $hostDir"

fi

# ===========================================================================
# ENSURE .local-host IS GIT-IGNORED
# ===========================================================================

gitignore_file="$NHL_REPO_ROOT/.gitignore"

touch "$gitignore_file"

if grep -qxF '.local-host/' "$gitignore_file"; then

    echo "$NOTE .local-host/ is already Git-ignored."

else

    printf '\n# Machine-local NixOS host configuration\n.local-host/\n' \
        >> "$gitignore_file"

    echo "$OK Added .local-host/ to .gitignore."

fi

# ===========================================================================
# VERIFY GIT IGNORE
# ===========================================================================

if git check-ignore -q "$localHostRoot"; then

    echo "$OK Confirmed .local-host/ is Git-ignored."

else

    echo "${ERROR} .local-host/ is not being ignored by Git."
    echo
    echo "${ERROR} Refusing to continue because machine-local configuration"
    echo "${ERROR} must never become part of the tracked repository."

    exit 1

fi

# ===========================================================================
# USERNAME
# ===========================================================================

if type nhl_resolve_install_username >/dev/null 2>&1; then
    installusername=$(nhl_resolve_install_username)
else
    installusername="${USER:-$(id -un)}"
fi

if [ -z "$installusername" ]; then
    echo "${ERROR} Unable to determine installation username."
    exit 1
fi

echo "$NOTE Installation username: $installusername"
echo "-----"

# ===========================================================================
# CREATE MACHINE-LOCAL HOST FILES
# ===========================================================================

required_host_files=(
    "config.nix"
    "variables.nix"
    "users.nix"
    "packages-fonts.nix"
    "hardware.nix"
)

echo "$NOTE Preparing machine-local host configuration..."

for host_file in "${required_host_files[@]}"; do

    target="$hostDir/$host_file"
    template="$NHL_REPO_ROOT/hosts/default/$host_file"

    if [ -f "$target" ]; then

        echo "$NOTE Preserving existing:"
        echo "    .local-host/$hostName/$host_file"

        continue
    fi

    if [ ! -f "$template" ]; then

        echo "${ERROR} Missing default template:"
        echo "    $template"

        exit 1
    fi

    cp "$template" "$target"

    echo "$OK Created:"
    echo "    .local-host/$hostName/$host_file"

done

echo "$OK Machine-local host template is complete."

# ===========================================================================
# FIX MACHINE-LOCAL MODULE IMPORT PATHS
#
# hosts/default/config.nix lives at:
#
#   hosts/default/config.nix
#
# so ../../modules/... is correct.
#
# .local-host/<hostname>/config.nix lives one directory shallower:
#
#   .local-host/<hostname>/config.nix
#
# therefore ../../modules/... is also correct.
#
# ../../../modules/... is WRONG from .local-host/<hostname>/config.nix
# because it escapes the repository.
#
# Older templates/local hosts may contain the incorrect ../../../ path.
# Normalize it here so existing installations are repaired automatically.
# ===========================================================================

local_config_file="$hostDir/config.nix"

if [ -f "$local_config_file" ]; then

    if grep -qE '\.\./\.\./\.\./modules/(drivers|hardware)' \
        "$local_config_file"; then

        echo "$WARN Correcting obsolete machine-local module import paths..."

        sed -i \
            -e 's#\.\./\.\./\.\./modules/drivers#../../modules/drivers#g' \
            -e 's#\.\./\.\./\.\./modules/hardware#../../modules/hardware#g' \
            "$local_config_file"

        echo "$OK Machine-local module import paths corrected."

    fi

fi

# ===========================================================================
# VERIFY MACHINE-LOCAL MODULE IMPORT PATHS
# ===========================================================================

if [ -f "$local_config_file" ]; then

    if grep -qE '\.\./\.\./\.\./modules/' "$local_config_file"; then

        echo "${ERROR} Invalid module import path remains in:"
        echo "    $local_config_file"

        grep -nE '\.\./\.\./\.\./modules/' "$local_config_file" || true

        echo
        echo "${ERROR} Refusing to continue with an invalid repository path."

        exit 1
    fi

    if grep -qE '\.\./\.\./modules/(drivers|hardware)' \
        "$local_config_file"; then

        echo "$OK Machine-local module imports point inside repository."

    fi

fi

# ===========================================================================
# HOST IDENTITY
# ===========================================================================

identity_file="$hostDir/identity.json"

cat > "$identity_file" <<EOF
{
  "username": "$installusername"
}
EOF

echo "$OK Host identity prepared:"
echo "    $identity_file"

echo "-----"

# ===========================================================================
# ENROLLMENT CHECK
# ===========================================================================

is_enrolled=0

if type nhl_is_enrolled_device >/dev/null 2>&1 \
    && nhl_is_enrolled_device "$hostName"; then

    is_enrolled=1

    echo "$NOTE Existing enrolled device detected for host '$hostName'."
    echo "$NOTE Reusing machine-local host profile."

fi

# ===========================================================================
# LOAD PREVIOUS INSTALLER STATE
# ===========================================================================

if type nhl_load_installer_state >/dev/null 2>&1 \
    && nhl_load_installer_state "$hostName"; then

    echo "$NOTE Loaded previous installer state for this host."

fi

# ===========================================================================
# GPU DETECTION
# ===========================================================================

if type nhl_detect_gpu_and_toggle >/dev/null 2>&1; then
    nhl_detect_gpu_and_toggle "$hostName"
fi

echo "-----"

# ===========================================================================
# KEYBOARD LAYOUT
# ===========================================================================

keyboardDefault="${NHL_STATE_KEYBOARD_LAYOUT:-de}"

if type nhl_read_input >/dev/null 2>&1; then

    keyboardLayout=$(
        nhl_read_input \
            "$CAT Enter your keyboard layout: [ ${keyboardDefault} ] " \
            "$keyboardDefault"
    )

else

    read -rp \
        "$CAT Enter your keyboard layout: [ ${keyboardDefault} ] " \
        keyboardLayout </dev/tty

    if [ -z "$keyboardLayout" ]; then
        keyboardLayout="$keyboardDefault"
    fi

fi

variables_file="$hostDir/variables.nix"

if [ ! -f "$variables_file" ]; then

    echo "${ERROR} Missing variables.nix:"
    echo "    $variables_file"

    exit 1

fi

if grep -qE '^[[:space:]]*keyboardLayout[[:space:]]*=' "$variables_file"; then

    sed -i \
        's/^[[:space:]]*keyboardLayout[[:space:]]*=[[:space:]]*"[^"]*"/  keyboardLayout = "'"$keyboardLayout"'"/' \
        "$variables_file"

else

    printf '\n  keyboardLayout = "%s";\n' "$keyboardLayout" \
        >> "$variables_file"

fi

echo "$OK Keyboard layout configured: $keyboardLayout"

# ===========================================================================
# TIMEZONE / CONSOLE KEYMAP
# ===========================================================================

if type nhl_prompt_timezone_console >/dev/null 2>&1; then
    nhl_prompt_timezone_console "$hostName" "$keyboardLayout"
fi

# ===========================================================================
# FINGERPRINT
# ===========================================================================

if type nhl_prompt_fingerprint >/dev/null 2>&1; then
    nhl_prompt_fingerprint "$hostName"
fi

# ===========================================================================
# VSCODE SYNC
# ===========================================================================

if type nhl_prompt_vscode_confirm_sync >/dev/null 2>&1; then
    nhl_prompt_vscode_confirm_sync "$hostName"
fi

echo "-----"

# ===========================================================================
# HOST IDENTITY UPDATE
# ===========================================================================

cat > "$identity_file" <<EOF
{
  "username": "$installusername"
}
EOF

echo "$OK Host identity updated:"
echo "    $identity_file"

# ===========================================================================
# HARDWARE CONFIGURATION
# ===========================================================================

echo "$NOTE Generating hardware configuration"

hardware_file="$hostDir/hardware.nix"

attempts=0
max_attempts=3

while [ "$attempts" -lt "$max_attempts" ]; do

    if [ "$is_enrolled" -eq 1 ] && [ -s "$hardware_file" ]; then

        echo "$NOTE Existing hardware configuration found for enrolled device."
        echo "$NOTE Keeping current hardware.nix."

        break

    fi

    if sudo nixos-generate-config \
        --show-hardware-config \
        >"$hardware_file" \
        2>/dev/null; then

        if [ -s "$hardware_file" ]; then

            echo "$OK Hardware configuration successfully generated:"
            echo "    $hardware_file"

            break

        fi

    fi

    rm -f "$hardware_file"

    attempts=$((attempts + 1))

    echo "${WARN} Failed to generate hardware configuration."
    echo "${WARN} Attempt $attempts of $max_attempts."

    if [ "$attempts" -ge "$max_attempts" ]; then

        echo "${ERROR} Unable to generate hardware configuration."
        exit 1

    fi

    sleep 1

done

echo "-----"

# ===========================================================================
# FIRMWARE
#
# Do not use the old helper here. Its current behavior can report that
# updates exist while immediately skipping the actual prompt.
#
# fwupdmgr get-updates:
#   - exit 0 with update information when updates are available
#   - prints that there are no updates otherwise
#
# We explicitly inspect the output and ask before running update.
# ===========================================================================

echo "$INFO Checking for available firmware updates..."

firmware_updates=""

if command -v fwupdmgr >/dev/null 2>&1; then

    firmware_updates="$(
        fwupdmgr get-updates 2>&1 || true
    )"

    if printf '%s\n' "$firmware_updates" \
        | grep -qiE \
            'No updatable devices|No updates available|Devices with no available firmware updates'; then

        echo "$NOTE No firmware updates are available; continuing without update prompt."

    else

        echo
        echo "$INFO Firmware update information:"
        printf '%s\n' "$firmware_updates"
        echo

        read -rp \
            "${CAT} Apply available firmware updates now? (y/N): ${RESET}" \
            firmware_answer </dev/tty

        if [[ "$firmware_answer" =~ ^[Yy]$ ]]; then

            echo "$NOTE Applying firmware updates..."

            if sudo fwupdmgr update; then

                echo "$OK Firmware update process completed."

            else

                echo "${WARN} Firmware update command failed."
                echo "${WARN} Continuing with installation."
                echo "${WARN} Review fwupd output above."

            fi

        else

            echo "$NOTE Firmware updates skipped."

        fi

    fi

else

    echo "$NOTE fwupdmgr is not available; skipping firmware updates."

fi

# ===========================================================================
# LUKS / TPM
#
# This is intentionally optional.
#
# A machine without LUKS must NOT fail installation.
# ===========================================================================

if type nhl_prompt_luks_tpm_setup >/dev/null 2>&1; then
    nhl_prompt_luks_tpm_setup "$hostName"
else
    echo "$NOTE LUKS/TPM helper is unavailable; skipping TPM enrollment."
fi

echo "-----"

# ===========================================================================
# SAVE INSTALLER STATE
# ===========================================================================

if type nhl_save_installer_state >/dev/null 2>&1; then

    nhl_save_installer_state \
        "$hostName" \
        "$keyboardLayout" \
        "${NHL_SELECTED_TIMEZONE:-}" \
        "${NHL_SELECTED_CONSOLE_KEYMAP:-$keyboardLayout}" \
        "${NHL_ENABLE_FINGERPRINT:-0}" \
        "${NHL_GPU_PROFILE:-}" \
        "${NHL_VSCODE_CONFIRM_SYNC:-true}" \
        "${NHL_SELECTED_HOSTNAME_MODE:-prefix-serial}" \
        "${NHL_SELECTED_HOSTNAME_PREFIX:-NixOS}" \
        "${hostName}"

fi

# ===========================================================================
# LEGACY STATE MIGRATION
# ===========================================================================

legacy_host_dir="$NHL_REPO_ROOT/hosts/$hostName"
legacy_state="$legacy_host_dir/.installer-state.json"
local_state="$hostDir/.installer-state.json"

if [ -f "$legacy_state" ]; then

    echo "$NOTE Found legacy installer state:"
    echo "    $legacy_state"

    if [ ! -f "$local_state" ]; then

        echo "$NOTE Migrating legacy installer state to:"
        echo "    $local_state"

        mv "$legacy_state" "$local_state"

        echo "$OK Installer state migrated."

    else

        echo "$NOTE Local installer state already exists."
        echo "$NOTE Keeping current .local-host state."

        rm -f "$legacy_state"

    fi

fi

# ===========================================================================
# LEGACY HOST DIRECTORY CLEANUP
# ===========================================================================

if [ -d "$legacy_host_dir" ]; then

    echo "$NOTE Removing obsolete legacy host directory:"
    echo "    $legacy_host_dir"

    for legacy_file in \
        config.nix \
        hardware.nix \
        packages-fonts.nix \
        users.nix \
        variables.nix \
        identity.json \
        .installer-state.json
    do
        rm -f "$legacy_host_dir/$legacy_file"
    done

    rmdir "$legacy_host_dir" 2>/dev/null || true

fi

# ===========================================================================
# VERIFY MACHINE-LOCAL FILES
# ===========================================================================

echo "-----"

echo "$NOTE Verifying machine-local host files..."

for host_file in "${required_host_files[@]}"; do

    if [ ! -f "$hostDir/$host_file" ]; then

        echo "${ERROR} Required machine-local file is missing:"
        echo "    $hostDir/$host_file"

        exit 1

    fi

done

if [ ! -f "$identity_file" ]; then

    echo "${ERROR} Missing host identity:"
    echo "    $identity_file"

    exit 1

fi

echo "$OK Machine-local host configuration is complete."

# ===========================================================================
# FLAKE VALIDATION
#
# IMPORTANT:
#
# .local-host/ is Git-ignored.
#
# Always use path:$NHL_REPO_ROOT.
# Do NOT use the normal git+file flake resolution here, because ignored
# machine-local files can disappear from a Git-based flake source.
# ===========================================================================

echo "-----"

echo "$NOTE Validating nixosConfigurations.$hostName..."

export NIX_CONFIG=$'experimental-features = nix-command flakes\nwarn-dirty = false'

flake_target="path:$NHL_REPO_ROOT#nixosConfigurations.\"${hostName}\""

# ---------------------------------------------------------------------------
# First verify that the configuration attribute exists.
# ---------------------------------------------------------------------------

if ! nix flake show "path:$NHL_REPO_ROOT" 2>/dev/null \
    | grep -q "nixosConfigurations.*${hostName}"; then

    echo
    echo "${ERROR} The flake does not expose:"
    echo "    nixosConfigurations.${hostName}"
    echo

    echo "${WARN} Machine-local host directory:"
    echo "    $hostDir"
    echo

    echo "${WARN} Files currently present:"

    find "$hostDir" \
        -maxdepth 1 \
        -type f \
        -printf '    %f\n' \
        | sort \
        || true

    echo

    echo "${NOTE} Current flake configurations:"
    nix flake show "path:$NHL_REPO_ROOT" 2>&1 || true

    echo

    echo "${ERROR} Installation cannot continue safely."

    exit 1

fi

echo "$OK Flake exposes nixosConfigurations.$hostName."

# ===========================================================================
# EVALUATE THE ACTUAL NIXOS CONFIGURATION
# ===========================================================================

echo "$NOTE Evaluating nixosConfigurations.$hostName..."

evaluation_error_file="$(mktemp)"

if ! nix eval \
    --show-trace \
    "${flake_target}.config.system.nixos.version" \
    > /dev/null \
    2>"$evaluation_error_file"; then

    echo
    echo "${ERROR} NixOS configuration exists but failed evaluation:"
    echo "    path:$NHL_REPO_ROOT#nixosConfigurations.${hostName}"
    echo

    echo "${NOTE} Showing evaluation error:"
    cat "$evaluation_error_file"

    rm -f "$evaluation_error_file"

    echo
    echo "${WARN} Machine-local host directory:"
    echo "    $hostDir"

    echo
    echo "${NOTE} Checking machine-local module imports..."

    grep -nE 'modules/(drivers|hardware)' \
        "$local_config_file" \
        || true

    echo

    echo "${ERROR} Installation cannot continue safely."

    exit 1

fi

rm -f "$evaluation_error_file"

echo "$OK NixOS configuration evaluation passed."

# ===========================================================================
# VERIFY GIT DOES NOT SEE MACHINE-LOCAL FILES
# ===========================================================================

echo "$NOTE Verifying machine-local configuration is not tracked..."

if git status --short --untracked-files=all -- "$localHostRoot" \
    | grep -q .; then

    echo "${ERROR} Git can see files under .local-host/."

    echo
    git status --short --untracked-files=all -- "$localHostRoot" || true
    echo

    echo "${ERROR} Refusing to continue."
    echo "${ERROR} Machine-local configuration must remain ignored."

    exit 1

fi

echo "$OK Machine-local configuration is safely ignored by Git."

# ===========================================================================
# STAGE TRACKED INSTALLER CHANGES
# ===========================================================================

echo "$NOTE Applying required Git settings before installation"

git config --global user.name "installer"
git config --global user.email "installer@gmail.com"

git add "$gitignore_file"

echo "$OK .gitignore staged."
echo "$OK Machine-local configuration remains Git-ignored."

# ===========================================================================
# FINAL FLAKE CHECK
# ===========================================================================

echo
echo "$NOTE Performing final flake validation..."

if ! nix eval \
    "${flake_target}.config.networking.hostName" \
    >/dev/null 2>&1; then

    echo "${ERROR} Final flake validation failed."
    echo

    echo "${ERROR} Expected:"
    echo "    nixosConfigurations.${hostName}"

    echo

    echo "${WARN} Machine-local host directory:"
    echo "    $hostDir"

    echo

    echo "${NOTE} Current flake configurations:"
    nix flake show "path:$NHL_REPO_ROOT" 2>&1 || true

    exit 1

fi

echo "$OK Final flake validation passed."

echo
echo "${INFO} Rebuild target:"
echo "    path:$NHL_REPO_ROOT#${hostName}"
echo

# ===========================================================================
# REBUILD
# ===========================================================================

printf "\n%.0s" {1..2}

echo "$NOTE Rebuilding NixOS. Please be patient..."
echo "-----"
echo "$CAT Build in progress. You can step away while this completes."
echo "-----"
echo "$NOTE Build is running. Monitor output for completion or errors."

printf "\n%.0s" {1..2}

echo "-----"

printf "\n%.0s" {1..1}

if ! sudo nixos-rebuild switch \
    --flake "path:$NHL_REPO_ROOT#${hostName}"; then

    echo
    echo "${ERROR} NixOS rebuild failed."
    echo

    echo "${WARN} Rebuild target:"
    echo "    path:$NHL_REPO_ROOT#${hostName}"

    echo

    echo "${NOTE} Available configurations:"
    nix flake show "path:$NHL_REPO_ROOT" 2>&1 || true

    echo

    exit 1

fi

echo "$OK NixOS rebuild completed successfully."

# ===========================================================================
# TPM ENROLLMENT
# ===========================================================================

if type nhl_run_luks_tpm_enrollment >/dev/null 2>&1; then
    nhl_run_luks_tpm_enrollment "$hostName"
fi

# ===========================================================================
# MARK DEVICE ENROLLED
# ===========================================================================

if type nhl_mark_device_enrolled >/dev/null 2>&1; then
    nhl_mark_device_enrolled "$hostName"
fi

# ===========================================================================
# FINGERPRINT ENROLLMENT
# ===========================================================================

if type nhl_enroll_fingerprint >/dev/null 2>&1; then
    nhl_enroll_fingerprint "$installusername"
fi

# ===========================================================================
# POST-INSTALL NOTES
# ===========================================================================

if type nhl_print_postinstall_notes >/dev/null 2>&1; then

    nhl_print_postinstall_notes \
        "$NHL_REPO_ROOT" \
        "$hostName"

fi

echo "-----"

printf "\n%.0s" {1..2}

# ===========================================================================
# ZSH CONFIGURATION
# ===========================================================================

if [ -f "$HOME/.zshrc" ]; then
    cp -b "$HOME/.zshrc" "$HOME/.zshrc-backup" || true
fi

if [ -f "$NHL_REPO_ROOT/assets/.zshrc" ]; then

    cp -f "$NHL_REPO_ROOT/assets/.zshrc" "$HOME/.zshrc"

else

    echo "${WARN} assets/.zshrc was not found. Skipping."

fi

# ===========================================================================
# GTK THEMES AND ICONS
# ===========================================================================

printf "Installing GTK-Themes and Icons..\n"

if [ -d "$NHL_REPO_ROOT/GTK-themes-icons" ]; then

    echo "$NOTE GTK themes and Icons directory exists..deleting..."

    rm -rf "$NHL_REPO_ROOT/GTK-themes-icons"

fi

echo "$NOTE Cloning GTK themes and Icons repository..."

if git clone \
    --depth 1 \
    https://github.com/JaKooLit/GTK-themes-icons.git \
    "$NHL_REPO_ROOT/GTK-themes-icons"; then

    cd "$NHL_REPO_ROOT/GTK-themes-icons"

    chmod +x auto-extract.sh

    if ./auto-extract.sh; then

        echo "$OK Extracted GTK Themes & Icons to ~/.icons & ~/.themes directories"

    else

        echo "$ERROR GTK theme extraction failed."

    fi

    cd "$NHL_REPO_ROOT"

else

    echo "$ERROR Download failed for GTK themes and Icons.."

fi

echo "-----"

printf "\n%.0s" {1..2}

# ===========================================================================
# USER CONFIG DIRECTORIES
# ===========================================================================

for DIR1 in gtk-3.0 Thunar xfce4; do

    DIRPATH="$HOME/.config/$DIR1"

    if [ -d "$DIRPATH" ]; then

        echo -e "${NOTE} Config for $DIR1 found, no need to copy."

    else

        echo -e "${NOTE} Config for $DIR1 not found, copying from assets."

        if cp -r "$NHL_REPO_ROOT/assets/$DIR1" "$HOME/.config/"; then

            echo "Copy $DIR1 completed!"

        else

            echo "Error: Failed to copy $DIR1 config files."

        fi

    fi

done

echo "-----"

printf "\n%.0s" {1..3}

# ===========================================================================
# CLEAN GTK TEMPORARY DIRECTORY
# ===========================================================================

if [ -d "$NHL_REPO_ROOT/GTK-themes-icons" ]; then

    echo "$NOTE GTK themes and Icons directory exists..deleting..."

    rm -rf "$NHL_REPO_ROOT/GTK-themes-icons"

fi

echo "-----"

printf "\n%.0s" {1..3}

# ===========================================================================
# HYPRLAND DOTS
# ===========================================================================

printf "$NOTE Downloading Hyprland-Dots to the home directory...\n"

if [ -d "$HOME/Hyprland-Dots" ]; then

    cd "$HOME/Hyprland-Dots"

    git stash || true
    git pull || true

    chmod +x copy.sh

    if ! ./copy.sh; then
        echo "${WARN} Hyprland-Dots copy.sh returned an error."
    fi

else

    if git clone \
        --depth 1 \
        https://github.com/JaKooLit/Hyprland-Dots \
        "$HOME/Hyprland-Dots"; then

        cd "$HOME/Hyprland-Dots"

        chmod +x copy.sh

        if ! ./copy.sh; then
            echo "${WARN} Hyprland-Dots copy.sh returned an error."
        fi

    else

        echo -e "$ERROR Failed to download Hyprland-Dots"

    fi

fi

# ===========================================================================
# RETURN TO REPOSITORY
# ===========================================================================

cd "$NHL_REPO_ROOT" || exit 1

# ===========================================================================
# FASTFETCH ASSETS
# ===========================================================================

if [ ! -f "$HOME/.config/fastfetch/nixos.png" ]; then

    if [ -d "$NHL_REPO_ROOT/assets/fastfetch" ]; then

        mkdir -p "$HOME/.config"

        cp -r "$NHL_REPO_ROOT/assets/fastfetch" "$HOME/.config/"

    else

        echo "${WARN} assets/fastfetch does not exist. Skipping."

    fi

fi

printf "\n%.0s" {1..2}

# ===========================================================================
# INSTALLATION COMPLETE
# ===========================================================================

if command -v Hyprland >/dev/null 2>&1; then

    printf "\n${OK} Installation completed successfully.${RESET}\n"

    if type nhl_print_recovery_key_and_confirm >/dev/null 2>&1; then
        nhl_print_recovery_key_and_confirm
    fi

    sleep 2

    printf "\n${NOTE} You can start Hyprland by running: Hyprland${RESET}\n"
    printf "\n${NOTE} A reboot is recommended to finalize all changes.${RESET}\n\n"

    read -rp \
        "${CAT} Would you like to reboot now? (y/n): ${RESET}" \
        HYP

    if [[ "$HYP" =~ ^[Yy]$ ]]; then

        systemctl reboot

    else

        echo "Reboot skipped."

    fi

else

    printf "\n${WARN} Hyprland failed to install. Please check Install-Logs...${RESET}\n\n"

    exit 1

fi
