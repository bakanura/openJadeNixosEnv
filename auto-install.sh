# Project source: https://github.com/LinuxBeginnings/NixOS-Hyprland

#!/usr/bin/env bash
clear

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NHL_REPO_ROOT="${HOME}/NixOS-Hyprland"

printf "\n%.0s" {1..2}
echo -e "\e[35m
	╦╔═┌─┐┌─┐╦    ╦ ╦┬ ┬┌─┐┬─┐┬  ┌─┐┌┐┌┌┬┐
	╠╩╗│ ││ │║    ╠═╣└┬┘├─┘├┬┘│  ├─┤│││ ││ 2025
	╩ ╩└─┘└─┘╩═╝  ╩ ╩ ┴ ┴  ┴└─┴─┘┴ ┴┘└┘─┴┘
\e[0m"
printf "\n%.0s" {1..1}

# Set some colors for output messages
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
# Helper: print the currently exported nixosConfigurations.
# ---------------------------------------------------------------------------
nhl_print_flake_configurations() {
    local repo_root="$1"

    echo
    echo "${NOTE} Available NixOS configurations:"
    echo "-----"

    if nix flake show --json "$repo_root" 2>/dev/null \
        | nix eval --impure --expr '
            let
              f = builtins.fromJSON (builtins.readFile /dev/stdin);
            in
              builtins.concatStringsSep "\n" (
                builtins.attrNames (f.nixosConfigurations or {})
              )
          ' 2>/dev/null; then
        :
    else
        # Fallback which works with normal flake output.
        nix flake show "$repo_root" 2>/dev/null \
            | sed -n '/nixosConfigurations/,/packages/p' \
            | sed -n 's/^[[:space:]]*├───\([^:]*\):.*$/\1/p' \
            || true
    fi

    echo "-----"
}

# ---------------------------------------------------------------------------
# Helper: validate that the requested host exists in the flake.
#
# This is the key fix for:
#
#   flake ... does not provide attribute
#   nixosConfigurations."hostname"
#
# Creating hosts/<hostname>/ is NOT enough. The flake itself must export
# nixosConfigurations.<hostname>.
# ---------------------------------------------------------------------------
nhl_validate_flake_host() {
    local repo_root="$1"
    local host="$2"

    echo "${NOTE} Checking flake configuration for host '${host}'..."

    if nix eval --raw \
        "${repo_root}#nixosConfigurations.${host}.config.networking.hostName" \
        >/dev/null 2>&1; then
        echo "${OK} Flake configuration '${host}' is available."
        return 0
    fi

    # Some configurations may not define networking.hostName. In that case
    # check the configuration itself.
    if nix eval \
        "${repo_root}#nixosConfigurations.${host}.config.system.build.toplevel" \
        >/dev/null 2>&1; then
        echo "${OK} Flake configuration '${host}' is available."
        return 0
    fi

    echo "${ERROR} Flake does not provide nixosConfigurations.${host}."
    echo

    echo "${WARN} The installer created:"
    echo "    ${repo_root}/hosts/${host}/"
    echo
    echo "${WARN} but that directory is not automatically exported by the flake."
    echo

    echo "${NOTE} Current flake output:"
    nix flake show "$repo_root" 2>&1 || true

    echo
    echo "${ERROR} Cannot safely rebuild '${host}' because the flake does not expose that configuration."
    return 1
}

# ---------------------------------------------------------------------------
# Helper: attempt to register a newly-created host in a simple
# nixosConfigurations attribute set.
#
# We deliberately refuse to modify complex/generated flake expressions.
# ---------------------------------------------------------------------------
nhl_register_host_in_flake() {
    local repo_root="$1"
    local host="$2"
    local flake_file="${repo_root}/flake.nix"
    local tmp_file

    if [ ! -f "$flake_file" ]; then
        echo "${ERROR} flake.nix not found at: ${flake_file}"
        return 1
    fi

    # Already exported? Nothing to do.
    if nix eval \
        "${repo_root}#nixosConfigurations.${host}.config.system.build.toplevel" \
        >/dev/null 2>&1; then
        echo "${OK} Host '${host}' is already exported by flake.nix."
        return 0
    fi

    echo "${NOTE} Host '${host}' is not currently exported by the flake."

    # -----------------------------------------------------------------------
    # First try the installer helper if the repository provides one.
    # -----------------------------------------------------------------------
    if type nhl_register_host >/dev/null 2>&1; then
        echo "${NOTE} Using repository host-registration helper..."

        if nhl_register_host "$repo_root" "$host"; then
            echo "${OK} Host '${host}' registered using nhl_register_host."
            return 0
        fi

        echo "${WARN} nhl_register_host did not register '${host}'."
    fi

    # -----------------------------------------------------------------------
    # Do not modify complex flake expressions automatically.
    #
    # We only support a straightforward:
    #
    #   nixosConfigurations = {
    #       ...
    #   };
    #
    # structure.
    # -----------------------------------------------------------------------
    if ! grep -Eq 'nixosConfigurations[[:space:]]*=[[:space:]]*\{' "$flake_file"; then
        echo "${WARN} flake.nix does not contain a simple:"
        echo "    nixosConfigurations = {"
        echo
        echo "${WARN} Automatic host registration was skipped."
        return 1
    fi

    # Find the line containing the opening nixosConfigurations set.
    local config_line
    config_line="$(
        grep -n -m1 \
            -E 'nixosConfigurations[[:space:]]*=[[:space:]]*\{' \
            "$flake_file" \
            | cut -d: -f1
    )"

    if [ -z "$config_line" ]; then
        echo "${ERROR} Unable to locate nixosConfigurations in flake.nix."
        return 1
    fi

    # -----------------------------------------------------------------------
    # We cannot safely invent the Nix expression for a host because different
    # versions of NixOS-Hyprland use different host constructors.
    #
    # Therefore look for an existing obvious host expression that we can
    # clone/reuse.
    # -----------------------------------------------------------------------
    local default_line
    default_line="$(
        grep -n -m1 \
            -E '^[[:space:]]*default[[:space:]]*=' \
            "$flake_file" \
            | cut -d: -f1
    )"

    if [ -z "$default_line" ]; then
        echo "${WARN} No simple 'default =' host was found in flake.nix."
        echo "${WARN} Refusing to invent a host expression."
        return 1
    fi

    local default_expr
    default_expr="$(
        sed -n "${default_line}p" "$flake_file"
    )"

    # Only permit a simple attribute assignment.
    if ! printf '%s\n' "$default_expr" \
        | grep -Eq '^[[:space:]]*default[[:space:]]*='; then
        echo "${WARN} Could not safely parse the default host expression."
        return 1
    fi

    # Replace only the attribute name:
    #
    #   default = ...
    #
    # becomes:
    #
    #   hostname = ...
    #
    # This preserves the actual host constructor used by the repository.
    local host_expr
    host_expr="$(
        printf '%s\n' "$default_expr" \
            | sed "s/^[[:space:]]*default[[:space:]]*=/    ${host} =/"
    )"

    if [ -z "$host_expr" ]; then
        echo "${ERROR} Failed to construct host expression."
        return 1
    fi

    tmp_file="$(mktemp)"

    # Insert the new host immediately after the nixosConfigurations opening.
    awk \
        -v target="$config_line" \
        -v expression="$host_expr" '
        NR == target {
            print
            print expression
            next
        }
        { print }
        ' "$flake_file" > "$tmp_file"

    if [ ! -s "$tmp_file" ]; then
        rm -f "$tmp_file"
        echo "${ERROR} Failed to modify flake.nix."
        return 1
    fi

    mv "$tmp_file" "$flake_file"

    echo "${OK} Added '${host}' to nixosConfigurations."

    # Validate immediately.
    if nix eval \
        "${repo_root}#nixosConfigurations.${host}.config.system.build.toplevel" \
        >/dev/null 2>&1; then
        echo "${OK} Successfully validated nixosConfigurations.${host}."
        return 0
    fi

    echo "${ERROR} Host was added to flake.nix, but the resulting configuration is invalid."
    echo
    echo "${WARN} The relevant flake section is:"
    sed -n "${config_line},$((config_line + 20))p" "$flake_file"
    echo

    return 1
}

# ---------------------------------------------------------------------------
# Helper: make sure the requested host exists in the flake.
# ---------------------------------------------------------------------------
nhl_prepare_flake_host() {
    local repo_root="$1"
    local host="$2"

    # First check whether it already exists.
    if nhl_validate_flake_host "$repo_root" "$host" >/dev/null 2>&1; then
        echo "${OK} Host '${host}' is already available in the flake."
        return 0
    fi

    echo "${NOTE} Attempting to register host '${host}' in the flake..."

    if ! nhl_register_host_in_flake "$repo_root" "$host"; then
        echo
        echo "${ERROR} Unable to prepare nixosConfigurations.${host}."
        echo "${ERROR} Installation cannot continue safely."
        return 1
    fi

    # Final validation.
    nhl_validate_flake_host "$repo_root" "$host"
}

# ---------------------------------------------------------------------------
# Load shared installer functions.
# ---------------------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/scripts/lib/install-common.sh" ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/scripts/lib/install-common.sh"
fi

# ---------------------------------------------------------------------------
# Verify this is NixOS.
# ---------------------------------------------------------------------------
if [ -n "$(grep -i nixos </etc/os-release)" ]; then
    echo "${OK} Verified this is NixOS."
    echo "-----"
else
    echo "$ERROR This is not NixOS or the distribution information is not available."
    exit 1
fi

nhl_ensure_required_packages

echo "$NOTE Switching to the home directory"
cd || exit

echo "-----"

backupname=$(date "+%Y-%m-%d-%H-%M-%S")

if [ -d "NixOS-Hyprland" ]; then
    echo "$NOTE NixOS-Hyprland exists, backing up to NixOS-Hyprland-backups directory."

    if [ -d "NixOS-Hyprland-backups" ]; then
        echo "Moving current version of NixOS-Hyprland to backups directory."
        sudo mv "$HOME/NixOS-Hyprland" \
            "$HOME/NixOS-Hyprland-backups/$backupname"
        sleep 1
    else
        echo "$NOTE Creating the backups directory & moving NixOS-Hyprland to it."
        mkdir -p "$HOME/NixOS-Hyprland-backups"
        sudo mv "$HOME/NixOS-Hyprland" \
            "$HOME/NixOS-Hyprland-backups/$backupname"
        sleep 1
    fi
else
    echo "$OK Proceeding with a fresh NixOS-Hyprland setup"
fi

echo "-----"

# ---------------------------------------------------------------------------
# Clone repository.
# ---------------------------------------------------------------------------
echo "$NOTE Cloning and entering the NixOS-Hyprland repository"

git clone --depth 1 \
    https://github.com/LinuxBeginnings/NixOS-Hyprland.git \
    "$HOME/NixOS-Hyprland"

cd "$HOME/NixOS-Hyprland" || exit

export NHL_REPO_ROOT="${HOME}/NixOS-Hyprland"

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

# ---------------------------------------------------------------------------
# Hostname.
# ---------------------------------------------------------------------------
if type nhl_prompt_hostname >/dev/null 2>&1; then
    hostName=$(nhl_prompt_hostname "NixOS")
elif type nhl_derive_hostname >/dev/null 2>&1; then
    hostName=$(nhl_derive_hostname "NixOS")
else
    hostName="UNKNOWN-HOST"
fi

echo "$NOTE Selected hostname: $hostName"

echo "-----"

# Resolve the username and write host identity BEFORE flake validation.
# The flake derives nixosConfigurations from the host identity metadata,
# so the identity must exist before nhl_preflight_fresh_install_target
# checks whether the host is exported.
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

# IMPORTANT:
# Create identity.json now, before any flake validation.
if type nhl_patch_flake_identity >/dev/null 2>&1; then
    if ! nhl_patch_flake_identity "$NHL_REPO_ROOT" "$hostName" "$installusername"; then
        echo "${ERROR} Failed to write host identity for '$hostName'."
        exit 1
    fi
else
    echo "${ERROR} nhl_patch_flake_identity is unavailable."
    exit 1
fi

echo "$OK Host identity prepared for hosts/$hostName/identity.json"
# Validate the dynamically-generated nixosConfigurations entry directly.
# Do NOT use nhl_preflight_fresh_install_target here because this flake
# generates nixosConfigurations from hostNames using builtins.listToAttrs.
echo "$NOTE Validating nixosConfigurations.$hostName..."

if ! NIX_CONFIG='experimental-features = nix-command flakes' \
    nix eval \
    --raw \
    "$NHL_REPO_ROOT#nixosConfigurations.\"${hostName}\".config.system.nixos.version" \
    >/dev/null; then

    echo "$ERROR The flake does not expose:"
    echo "    nixosConfigurations.$hostName"
    echo "$ERROR Installation cannot continue safely."
    exit 1
fi

echo "$OK Flake exports nixosConfigurations.$hostName."

# Reuse an existing host profile when the device is already enrolled.
is_enrolled=0
if type nhl_is_enrolled_device >/dev/null 2>&1 && nhl_is_enrolled_device "$hostName"; then
    is_enrolled=1
    echo "$NOTE Existing enrolled device detected for host '$hostName'. Reusing host profile."
fi

# Create or repair the host profile.
if [ ! -d "hosts/$hostName" ]; then
    mkdir -p "hosts/$hostName"
    echo "$NOTE Created host directory hosts/$hostName."
fi

for host_file in config.nix variables.nix; do
    if [ ! -f "hosts/$hostName/$host_file" ]; then
        if [ -f "hosts/default/$host_file" ]; then
            cp "hosts/default/$host_file" "hosts/$hostName/$host_file"
            echo "$OK Created hosts/$hostName/$host_file from default."
        else
            echo "$ERROR Required template hosts/default/$host_file does not exist."
            exit 1
        fi
    else
        echo "$NOTE Preserving existing hosts/$hostName/$host_file."
    fi
done

echo "$OK Host profile is ready at hosts/$hostName."

# ---------------------------------------------------------------------------
# Load previous installer state.
# ---------------------------------------------------------------------------
if type nhl_load_installer_state >/dev/null 2>&1 \
    && nhl_load_installer_state "$hostName"; then

    echo "$NOTE Loaded previous installer state for this host."
fi

# ---------------------------------------------------------------------------
# Detect GPU/VM profile and apply host toggles.
# ---------------------------------------------------------------------------
if type nhl_detect_gpu_and_toggle >/dev/null 2>&1; then
    nhl_detect_gpu_and_toggle "$hostName"
fi

echo "-----"

# ---------------------------------------------------------------------------
# Keyboard layout.
# ---------------------------------------------------------------------------
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

variables_file="$NHL_REPO_ROOT/hosts/$hostName/variables.nix"

if [ ! -f "$variables_file" ]; then
    echo "${ERROR} Missing required host variables file:"
    echo "        $variables_file"
    exit 1
fi

if grep -qE 'keyboardLayout\s*=' "$variables_file"; then
    sed -i \
        's/keyboardLayout\s*=\s*"[^"]*"/keyboardLayout = "'"$keyboardLayout"'"/' \
        "$variables_file"
else
    echo 'keyboardLayout = "'"$keyboardLayout"'"' >> "$variables_file"
fi

echo "$OK Keyboard layout configured: $keyboardLayout"


# ---------------------------------------------------------------------------
# Configure timezone and console keymap.
# ---------------------------------------------------------------------------
if type nhl_prompt_timezone_console >/dev/null 2>&1; then
    nhl_prompt_timezone_console "$hostName" "$keyboardLayout"
fi

if type nhl_prompt_fingerprint >/dev/null 2>&1; then
    nhl_prompt_fingerprint "$hostName"
fi

if type nhl_prompt_vscode_confirm_sync >/dev/null 2>&1; then
    nhl_prompt_vscode_confirm_sync "$hostName"
fi

echo "-----"

# ---------------------------------------------------------------------------
# Resolve installation username.
# ---------------------------------------------------------------------------
if type nhl_resolve_install_username >/dev/null 2>&1; then
    installusername=$(nhl_resolve_install_username)
else
    installusername="${USER}"
fi

# ---------------------------------------------------------------------------
# Update host identity BEFORE staging git changes.
# ---------------------------------------------------------------------------
if type nhl_patch_flake_identity >/dev/null 2>&1; then
    nhl_patch_flake_identity \
        "$NHL_REPO_ROOT" \
        "$hostName" \
        "$installusername"
fi

# ---------------------------------------------------------------------------
# Generate hardware configuration.
# ---------------------------------------------------------------------------
echo "$NOTE Generating hardware configuration"

attempts=0
max_attempts=3
hardware_file="./hosts/$hostName/hardware.nix"

while [ "$attempts" -lt "$max_attempts" ]; do

    if [ "$is_enrolled" -eq 1 ] && [ -s "$hardware_file" ]; then
        echo "${NOTE} Existing hardware configuration found for enrolled device; keeping current file."
        break
    fi

    sudo nixos-generate-config \
        --show-hardware-config \
        >"$hardware_file" \
        2>/dev/null \
        || rm -f "$hardware_file"

    if [ -s "$hardware_file" ]; then
        echo "${OK} Hardware configuration successfully generated."
        break
    fi

    echo "${WARN} Failed to generate hardware configuration. Attempt $((attempts + 1)) of $max_attempts."

    attempts=$((attempts + 1))

    if [ "$attempts" -eq "$max_attempts" ]; then
        echo "${ERROR} Unable to generate hardware configuration after $max_attempts attempts."
        exit 1
    fi
done

echo "-----"

# ---------------------------------------------------------------------------
# Firmware.
# ---------------------------------------------------------------------------
if type nhl_prompt_firmware_updates >/dev/null 2>&1; then
    nhl_prompt_firmware_updates
fi

# ---------------------------------------------------------------------------
# LUKS / TPM setup.
# ---------------------------------------------------------------------------
if type nhl_prompt_luks_tpm_setup >/dev/null 2>&1; then
    nhl_prompt_luks_tpm_setup "$hostName"
fi

echo "-----"

# ---------------------------------------------------------------------------
# Save installer state.
# ---------------------------------------------------------------------------
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

echo "$NOTE Applying required Nix settings before installation"

git config --global user.name "installer"
git config --global user.email "installer@gmail.com"

# Stage the generated host configuration.
git add .

# identity.json was already created before flake preflight.
echo "$OK Host identity written to hosts/$hostName/identity.json"

# ---------------------------------------------------------------------------
# Make sure the generated host is actually exposed by the flake.
#
# This is the fix for:
#
#   does not provide attribute
#   nixosConfigurations."bakadesk-2657013e362a"
# ---------------------------------------------------------------------------
echo
echo "$NOTE Preparing flake configuration for host '$hostName'..."

if ! nhl_prepare_flake_host "$NHL_REPO_ROOT" "$hostName"; then
    echo
    echo "${ERROR} Cannot continue with installation."
    echo "${ERROR} The flake does not expose:"
    echo "    nixosConfigurations.${hostName}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Stage ALL modifications only after host registration and identity changes.
# ---------------------------------------------------------------------------
git add .

echo "$OK Installer changes staged."

# ---------------------------------------------------------------------------
# Show exactly what will be used for the rebuild.
# ---------------------------------------------------------------------------
echo
echo "${INFO} Rebuild target:"
echo "    ${NHL_REPO_ROOT}#${hostName}"
echo

# ---------------------------------------------------------------------------
# Set Nix CLI behavior for installer execution.
# ---------------------------------------------------------------------------
export NIX_CONFIG=$'experimental-features = nix-command flakes\nwarn-dirty = false'

# ---------------------------------------------------------------------------
# Final flake validation immediately before rebuild.
# ---------------------------------------------------------------------------
if ! nhl_validate_flake_host "$NHL_REPO_ROOT" "$hostName"; then
    echo "${ERROR} Final flake validation failed."
    exit 1
fi

printf "\n%.0s" {1..2}

echo "$NOTE Rebuilding NixOS. Please be patient..."
echo "-----"
echo "$CAT Build in progress. You can step away while this completes."
echo "-----"
echo "$NOTE Build is running. Monitor output for completion or errors."

printf "\n%.0s" {1..2}

echo "-----"

printf "\n%.0s" {1..1}

# ---------------------------------------------------------------------------
# NixOS rebuild.
# ---------------------------------------------------------------------------
if ! sudo nixos-rebuild switch \
    --flake "$NHL_REPO_ROOT#${hostName}"; then

    echo
    echo "${ERROR} NixOS rebuild failed."
    echo
    echo "${WARN} The requested configuration was:"
    echo "    ${NHL_REPO_ROOT}#${hostName}"
    echo
    echo "${NOTE} Available configurations are:"
    nix flake show "$NHL_REPO_ROOT" 2>&1 || true
    echo
    exit 1
fi

# ---------------------------------------------------------------------------
# Post-rebuild enrollment.
# ---------------------------------------------------------------------------
if type nhl_run_luks_tpm_enrollment >/dev/null 2>&1; then
    nhl_run_luks_tpm_enrollment "$hostName"
fi

if type nhl_mark_device_enrolled >/dev/null 2>&1; then
    nhl_mark_device_enrolled "$hostName"
fi

if type nhl_enroll_fingerprint >/dev/null 2>&1; then
    nhl_enroll_fingerprint "$installusername"
fi

if type nhl_print_postinstall_notes >/dev/null 2>&1; then
    nhl_print_postinstall_notes \
        "$NHL_REPO_ROOT" \
        "$hostName"
fi

echo "-----"

printf "\n%.0s" {1..2}

# ---------------------------------------------------------------------------
# Prepare initial Zsh configuration.
# ---------------------------------------------------------------------------
if [ -f "$HOME/.zshrc" ]; then
    cp -b "$HOME/.zshrc" "$HOME/.zshrc-backup" || true
fi

cp -r "assets/.zshrc" "$HOME/"

# ---------------------------------------------------------------------------
# Install GTK themes and icons.
# ---------------------------------------------------------------------------
printf "Installing GTK-Themes and Icons..\n"

if [ -d "GTK-themes-icons" ]; then
    echo "$NOTE GTK themes and Icons directory exist..deleting..."
    rm -rf "GTK-themes-icons"
fi

echo "$NOTE Cloning GTK themes and Icons repository..."

if git clone \
    --depth 1 \
    https://github.com/JaKooLit/GTK-themes-icons.git; then

    cd GTK-themes-icons

    chmod +x auto-extract.sh
    ./auto-extract.sh

    cd "$NHL_REPO_ROOT"

    echo "$OK Extracted GTK Themes & Icons to ~/.icons & ~/.themes directories"

else
    echo "$ERROR Download failed for GTK themes and Icons.."
fi

echo "-----"

printf "\n%.0s" {1..2}

# ---------------------------------------------------------------------------
# Copy missing user configuration directories from assets.
# ---------------------------------------------------------------------------
for DIR1 in gtk-3.0 Thunar xfce4; do

    DIRPATH="$HOME/.config/$DIR1"

    if [ -d "$DIRPATH" ]; then
        echo -e "${NOTE} Config for $DIR1 found, no need to copy."
    else
        echo -e "${NOTE} Config for $DIR1 not found, copying from assets."

        if cp -r "assets/$DIR1" "$HOME/.config/"; then
            echo "Copy $DIR1 completed!"
        else
            echo "Error: Failed to copy $DIR1 config files."
        fi
    fi
done

echo "-----"

printf "\n%.0s" {1..3}

# ---------------------------------------------------------------------------
# Clean up temporary GTK themes and icons clone.
# ---------------------------------------------------------------------------
if [ -d "GTK-themes-icons" ]; then
    echo "$NOTE GTK themes and Icons directory exist..deleting..."
    rm -rf "GTK-themes-icons"
fi

echo "-----"

printf "\n%.0s" {1..3}

# ---------------------------------------------------------------------------
# Sync Hyprland-Dots into the home directory.
# ---------------------------------------------------------------------------
printf "$NOTE Downloading Hyprland-Dots to the home directory...\n"

if [ -d "$HOME/Hyprland-Dots" ]; then

    cd "$HOME/Hyprland-Dots"

    git stash
    git pull

    chmod +x copy.sh
    ./copy.sh

else

    if git clone \
        --depth 1 \
        https://github.com/JaKooLit/Hyprland-Dots \
        "$HOME/Hyprland-Dots"; then

        cd "$HOME/Hyprland-Dots" || exit 1

        chmod +x copy.sh
        ./copy.sh

    else
        echo -e "$ERROR Failed to download Hyprland-Dots"
    fi
fi

# ---------------------------------------------------------------------------
# Return to NixOS-Hyprland.
# ---------------------------------------------------------------------------
cd "$NHL_REPO_ROOT" || exit 1

# ---------------------------------------------------------------------------
# Install fastfetch assets when missing.
# ---------------------------------------------------------------------------
if [ ! -f "$HOME/.config/fastfetch/nixos.png" ]; then
    cp -r assets/fastfetch "$HOME/.config/"
fi

printf "\n%.0s" {1..2}

# ---------------------------------------------------------------------------
# Installation complete.
# ---------------------------------------------------------------------------
if command -v Hyprland &>/dev/null; then

    printf "\n${OK} Installation completed successfully.${RESET}\n"

    if type nhl_print_recovery_key_and_confirm >/dev/null 2>&1; then
        nhl_print_recovery_key_and_confirm
    fi

    sleep 2

    printf "\n${NOTE} You can start Hyprland by running: Hyprland${RESET}\n"
    printf "\n${NOTE} A reboot is recommended to finalize all changes.${RESET}\n\n"

    # Prompt user to reboot.
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
