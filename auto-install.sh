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
#
# auto-install.sh is expected to be running from the cloned repository.
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

# ===========================================================================
# LOCAL HOST DIRECTORY
#
# Repository layout:
#
#   hosts/
#   └── default/
#       ├── config.nix
#       ├── hardware.nix
#       ├── packages-fonts.nix
#       ├── users.nix
#       └── variables.nix
#
#   .local-host/
#   └── <hostname>/
#       ├── identity.json
#       ├── hardware.nix
#       ├── config.nix
#       ├── packages-fonts.nix
#       ├── users.nix
#       ├── variables.nix
#       └── .installer-state.json
#
# hosts/default is centrally managed and Git-tracked.
#
# .local-host is machine-specific and MUST be Git-ignored.
#
# hostDir is the single source of truth for all machine-local files.
# ===========================================================================

localHostRoot="$NHL_REPO_ROOT/.local-host"
hostDir="$localHostRoot/$hostName"

# Export these so shared installer functions can use the exact same location.
export NHL_LOCAL_HOST_ROOT="$localHostRoot"
export NHL_HOST_DIR="$hostDir"

echo "-----"
echo "$NOTE Machine-local configuration root:"
echo "    $localHostRoot"

if [ ! -d "$localHostRoot" ]; then
    echo "$NOTE Creating machine-local host root..."
    mkdir -p "$localHostRoot"
    echo "$OK Created .local-host/"
fi

if [ -d "$hostDir" ]; then

    echo "$NOTE Local host directory already exists:"
    echo "    $hostDir"
    echo "$NOTE Preserving existing machine-specific files."

else

    echo "$NOTE Creating local host directory:"
    echo "    $hostDir"

    mkdir -p "$hostDir"

    echo "$OK Created .local-host/$hostName/"

fi

# ===========================================================================
# ENSURE .local-host IS GIT-IGNORED
#
# This is intentionally handled by the installer so a fresh clone is safe.
# ===========================================================================

gitignore_file="$NHL_REPO_ROOT/.gitignore"

touch "$gitignore_file"

if ! grep -qxF '.local-host/' "$gitignore_file"; then
    printf '\n# Machine-local NixOS host configuration\n.local-host/\n' \
        >> "$gitignore_file"

    echo "$OK Added .local-host/ to .gitignore."
else
    echo "$NOTE .local-host/ is already Git-ignored."
fi

# ===========================================================================
# CREATE HOST TEMPLATE FILES
#
# The machine-local host starts from hosts/default/.
#
# These files are copied once. Existing machine-specific versions are
# preserved on subsequent installer runs.
# ===========================================================================

required_host_files=(
    "config.nix"
    "variables.nix"
    "users.nix"
    "packages-fonts.nix"
    "hardware.nix"
)

for host_file in "${required_host_files[@]}"; do

    target="$hostDir/$host_file"
    template="$NHL_REPO_ROOT/hosts/default/$host_file"

    if [ -f "$target" ]; then
        echo "$NOTE Preserving existing .local-host/$hostName/$host_file"
        continue
    fi

    if [ ! -f "$template" ]; then
        echo "${ERROR} Missing default template:"
        echo "        $template"
        exit 1
    fi

    cp "$template" "$target"

    echo "$OK Created .local-host/$hostName/$host_file"

done

echo "$OK Local host template is complete."

# ===========================================================================
# HOST IDENTITY
#
# identity.json is machine-local and therefore belongs in .local-host/.
#
# Do NOT patch flake.nix.
# Do NOT write identity.json into hosts/.
# ===========================================================================

identity_file="$hostDir/identity.json"

if [ -f "$identity_file" ]; then

    echo "$NOTE Existing host identity found:"
    echo "    $identity_file"

else

    cat > "$identity_file" <<EOF
{
  "username": "$installusername"
}
EOF

    echo "$OK Created .local-host/$hostName/identity.json"

fi

# Always make sure the current installation username is represented.
cat > "$identity_file" <<EOF
{
  "username": "$installusername"
}
EOF

echo "$OK Host identity prepared for .local-host/$hostName/identity.json"

echo "-----"

# ===========================================================================
# ENROLLMENT CHECK
# ===========================================================================

is_enrolled=0

if type nhl_is_enrolled_device >/dev/null 2>&1 \
    && nhl_is_enrolled_device "$hostName"; then

    is_enrolled=1

    echo "$NOTE Existing enrolled device detected for host '$hostName'."
    echo "$NOTE Reusing host profile."

fi

# ===========================================================================
# LOAD PREVIOUS INSTALLER STATE
#
# Shared installer functions should use NHL_HOST_DIR.
#
# The state file belongs beside identity.json:
#
#   .local-host/<hostname>/.installer-state.json
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
    echo "        $variables_file"
    exit 1
fi

# Safely update keyboardLayout.
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
# IDENTITY UPDATE
#
# Keep identity handling entirely local.
# ===========================================================================

cat > "$identity_file" <<EOF
{
  "username": "$installusername"
}
EOF

echo "$OK Host identity updated."

# ===========================================================================
# HARDWARE CONFIGURATION
#
# This is machine-specific and therefore belongs in:
#
#   .local-host/<hostname>/hardware.nix
# ===========================================================================

echo "$NOTE Generating hardware configuration"

hardware_file="$hostDir/hardware.nix"

attempts=0
max_attempts=3

while [ "$attempts" -lt "$max_attempts" ]; do

    # Existing enrolled machine: don't overwrite known-good hardware config.
    if [ "$is_enrolled" -eq 1 ] && [ -s "$hardware_file" ]; then

        echo "$NOTE Existing hardware configuration found for enrolled device."
        echo "$NOTE Keeping current hardware.nix."

        break

    fi

    # Fresh installation: generate hardware configuration.
    if sudo nixos-generate-config \
        --show-hardware-config \
        >"$hardware_file" \
        2>/dev/null; then

        if [ -s "$hardware_file" ]; then

            echo "$OK Hardware configuration successfully generated."
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
# ===========================================================================

if type nhl_prompt_firmware_updates >/dev/null 2>&1; then
    nhl_prompt_firmware_updates
fi

# ===========================================================================
# LUKS / TPM
# ===========================================================================

if type nhl_prompt_luks_tpm_setup >/dev/null 2>&1; then
    nhl_prompt_luks_tpm_setup "$hostName"
fi

echo "-----"

# ===========================================================================
# SAVE INSTALLER STATE
#
# State belongs in .local-host/<hostname>/.
#
# NHL_HOST_DIR is exported above so the common function can use it.
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
# SAFETY CHECK FOR LOCAL STATE
#
# If the shared function still uses its legacy location, move the generated
# state into .local-host/.
# ===========================================================================

legacy_state="$NHL_REPO_ROOT/hosts/$hostName/.installer-state.json"
local_state="$hostDir/.installer-state.json"

if [ -f "$legacy_state" ] && [ "$legacy_state" != "$local_state" ]; then

    echo "$NOTE Migrating legacy installer state to .local-host/"

    mv "$legacy_state" "$local_state"

    if [ -d "$NHL_REPO_ROOT/hosts/$hostName" ]; then
        rmdir "$NHL_REPO_ROOT/hosts/$hostName" 2>/dev/null || true
    fi

    echo "$OK Installer state moved to:"
    echo "    $local_state"

fi

# ===========================================================================
# FLAKE VALIDATION
#
# IMPORTANT:
#
# .local-host is intentionally Git-ignored.
#
# Therefore:
#
#   nix eval "$NHL_REPO_ROOT#..."
#
# is NOT safe here because Nix may interpret the repository as git+file and
# omit ignored files.
#
# We explicitly use:
#
#   path:$NHL_REPO_ROOT
#
# which makes Nix evaluate the complete local filesystem tree, including
# .local-host/.
# ===========================================================================

echo "-----"

echo "$NOTE Validating nixosConfigurations.$hostName..."

export NIX_CONFIG=$'experimental-features = nix-command flakes\nwarn-dirty = false'

flake_target="path:$NHL_REPO_ROOT#nixosConfigurations.\"${hostName}\""

if ! nix eval \
    --raw \
    "${flake_target}.config.system.nixos.version" \
    >/dev/null 2>&1; then

    echo
    echo "${ERROR} The flake does not expose:"
    echo "    nixosConfigurations.${hostName}"
    echo

    echo "${WARN} Local host directory:"
    echo "    $hostDir"
    echo

    echo "${WARN} Files currently present:"
    find "$hostDir" -maxdepth 1 -type f -printf '    %f\n' \
        | sort \
        || true

    echo

    echo "${NOTE} Current flake configurations:"

    nix flake show "path:$NHL_REPO_ROOT" 2>&1 || true

    echo

    echo "${ERROR} Installation cannot continue safely."
    exit 1

fi

echo "$OK Flake exports nixosConfigurations.$hostName."

# ===========================================================================
# STAGE TRACKED INSTALLER CHANGES
#
# NEVER git-add .local-host/.
#
# The .gitignore entry itself is tracked, while machine-local configuration
# remains private to the installation.
# ===========================================================================

echo "$NOTE Applying required Nix settings before installation"

git config --global user.name "installer"
git config --global user.email "installer@gmail.com"

git add .gitignore

echo "$OK Machine-local configuration remains Git-ignored."

# ===========================================================================
# FINAL FLAKE CHECK
# ===========================================================================

echo
echo "$NOTE Performing final flake validation..."

if ! nix eval \
    --raw \
    "${flake_target}.config.networking.hostName" \
    >/dev/null 2>&1; then

    echo "${ERROR} Final flake validation failed."
    echo
    echo "${ERROR} Expected:"
    echo "    nixosConfigurations.${hostName}"
    echo
    echo "${WARN} Local host directory:"
    echo "    $hostDir"
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
