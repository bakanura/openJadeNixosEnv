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

# Load shared installer functions.
if [ -f "${SCRIPT_DIR}/scripts/lib/install-common.sh" ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/scripts/lib/install-common.sh"
fi

# Verify this is NixOS.
if [ -n "$(grep -i nixos </etc/os-release)" ]; then
    echo "${OK} Verified this is NixOS."
    echo "-----"
else
    echo "$ERROR This is not NixOS or the distribution information is not available."
    exit 1

nhl_ensure_required_packages

echo "$NOTE Switching to the home directory"
cd || exit

echo "-----"

backupname=$(date "+%Y-%m-%d-%H-%M-%S")
if [ -d "NixOS-Hyprland" ]; then
    echo "$NOTE NixOS-Hyprland exists, backing up to NixOS-Hyprland-backups directory."
    if [ -d "NixOS-Hyprland-backups" ]; then
        echo "Moving current version of NixOS-Hyprland to backups directory."
        sudo mv "$HOME"/NixOS-Hyprland NixOS-Hyprland-backups/"$backupname"
        sleep 1
    else
        echo "$NOTE Creating the backups directory & moving NixOS-Hyprland to it."
        mkdir -p NixOS-Hyprland-backups
        sudo mv "$HOME"/NixOS-Hyprland NixOS-Hyprland-backups/"$backupname"
        sleep 1
    fi
else
    echo "$OK Proceeding with a fresh NixOS-Hyprland setup"
fi

echo "-----"

echo "$NOTE Cloning and entering the NixOS-Hyprland repository"
git clone --depth 1 https://github.com/LinuxBeginnings/NixOS-Hyprland.git ~/NixOS-Hyprland
cd ~/NixOS-Hyprland || exit
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

if type nhl_prompt_hostname >/dev/null 2>&1; then
    hostName=$(nhl_prompt_hostname "NixOS")
elif type nhl_derive_hostname >/dev/null 2>&1; then
    hostName=$(nhl_derive_hostname "NixOS")
else
    hostName="UNKNOWN-HOST"
fi
echo "$NOTE Selected hostname: $hostName"

echo "-----"

if type nhl_preflight_fresh_install_target >/dev/null 2>&1; then
    nhl_preflight_fresh_install_target "${NHL_REPO_ROOT}" "$hostName" || exit 1
fi

# Reuse an existing host profile when the device is already enrolled.
is_enrolled=0
if type nhl_is_enrolled_device >/dev/null 2>&1 && nhl_is_enrolled_device "$hostName"; then
    is_enrolled=1
    echo "$NOTE Existing enrolled device detected for host '$hostName'. Reusing host profile."
fi

if [ $is_enrolled -eq 0 ]; then
    if [ ! -d "hosts/$hostName" ]; then
        mkdir -p hosts/"$hostName"
        cp hosts/default/*.nix hosts/"$hostName"
        echo "$OK Created new host profile at hosts/$hostName."
    else
        echo "$NOTE Host directory hosts/$hostName already exists; preserving existing files."
    fi
fi

if type nhl_load_installer_state >/dev/null 2>&1 && nhl_load_installer_state "$hostName"; then
    echo "$NOTE Loaded previous installer state for this host."
fi

# Detect GPU/VM profile and apply host toggles.
if type nhl_detect_gpu_and_toggle >/dev/null 2>&1; then
    nhl_detect_gpu_and_toggle "$hostName"
fi
echo "-----"

keyboardDefault="${NHL_STATE_KEYBOARD_LAYOUT:-de}"
if type nhl_read_input >/dev/null 2>&1; then
    keyboardLayout=$(nhl_read_input "$CAT Enter your keyboard layout: [ ${keyboardDefault} ] " "$keyboardDefault")
else
    read -rp "$CAT Enter your keyboard layout: [ ${keyboardDefault} ] " keyboardLayout </dev/tty
    if [ -z "$keyboardLayout" ]; then
        keyboardLayout="$keyboardDefault"
    fi
fi

sed -i 's/keyboardLayout\s*=\s*"\([^"]*\)"/keyboardLayout = "'"$keyboardLayout"'"/' ./hosts/$hostName/variables.nix

# Configure timezone and console keymap.
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

if type nhl_resolve_install_username >/dev/null 2>&1; then
    installusername=$(nhl_resolve_install_username)
else
    installusername=$(echo $USER)
fi
if type nhl_patch_flake_identity >/dev/null 2>&1; then
    nhl_patch_flake_identity "$NHL_REPO_ROOT" "$hostName" "$installusername"
fi

echo "$NOTE Generating hardware configuration"
attempts=0
max_attempts=3
hardware_file="./hosts/$hostName/hardware.nix"

while [ $attempts -lt $max_attempts ]; do
    if [ $is_enrolled -eq 1 ] && [ -s "$hardware_file" ]; then
        echo "${NOTE} Existing hardware configuration found for enrolled device; keeping current file."
        break
    fi

    sudo nixos-generate-config --show-hardware-config >"$hardware_file" 2>/dev/null || rm -f "$hardware_file"

    if [ -s "$hardware_file" ]; then
        echo "${OK} Hardware configuration successfully generated."
        break
    else
        echo "${WARN} Failed to generate hardware configuration. Attempt $(($attempts + 1)) of $max_attempts."
        attempts=$(($attempts + 1))

        # Exit if this was the last attempt
        if [ $attempts -eq $max_attempts ]; then
            echo "${ERROR} Unable to generate hardware configuration after $max_attempts attempts."
            exit 1
        fi
    fi
done

echo "-----"

if type nhl_prompt_firmware_updates >/dev/null 2>&1; then
    nhl_prompt_firmware_updates
fi

if type nhl_prompt_luks_tpm_setup >/dev/null 2>&1; then
    nhl_prompt_luks_tpm_setup "$hostName"
fi

echo "-----"

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
git add .
# Update the host identity metadata (username for this host).
if type nhl_patch_flake_identity >/dev/null 2>&1; then
    nhl_patch_flake_identity "$NHL_REPO_ROOT" "$hostName" "$installusername"
fi
echo "$OK Host identity written to hosts/$hostName/identity.json"

printf "\n%.0s" {1..2}

echo "$NOTE Rebuilding NixOS. Please be patient..."
echo "-----"
echo "$CAT Build in progress. You can step away while this completes."
echo "-----"
echo "$NOTE Build is running. Monitor output for completion or errors."
printf "\n%.0s" {1..2}
echo "-----"
printf "\n%.0s" {1..1}

# Set Nix CLI behavior for installer execution.
export NIX_CONFIG=$'experimental-features = nix-command flakes\nwarn-dirty = false'
#sudo nix flake update
sudo nixos-rebuild switch --flake ~/NixOS-Hyprland/#"${hostName}"

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
    nhl_print_postinstall_notes "$NHL_REPO_ROOT" "$hostName"
fi

echo "-----"
printf "\n%.0s" {1..2}

# Prepare initial Zsh configuration.
# Check if ~/.zshrc and  exists, create a backup, and copy the new configuration
if [ -f "$HOME/.zshrc" ]; then
    cp -b "$HOME/.zshrc" "$HOME/.zshrc-backup" || true
fi

# Copy the predefined Zsh profile.
cp -r 'assets/.zshrc' ~/

# Install GTK themes and icons.
printf "Installing GTK-Themes and Icons..\n"

if [ -d "GTK-themes-icons" ]; then
    echo "$NOTE GTK themes and Icons directory exist..deleting..."
    rm -rf "GTK-themes-icons"
fi

echo "$NOTE Cloning GTK themes and Icons repository..."
if git clone --depth 1 https://github.com/JaKooLit/GTK-themes-icons.git; then
    cd GTK-themes-icons
    chmod +x auto-extract.sh
    ./auto-extract.sh
    cd ..
    echo "$OK Extracted GTK Themes & Icons to ~/.icons & ~/.themes directories"
else
    echo "$ERROR Download failed for GTK themes and Icons.."
fi

echo "-----"
printf "\n%.0s" {1..2}

# Copy missing user configuration directories from assets.
for DIR1 in gtk-3.0 Thunar xfce4; do
    DIRPATH=~/.config/$DIR1
    if [ -d "$DIRPATH" ]; then
        echo -e "${NOTE} Config for $DIR1 found, no need to copy."
    else
        echo -e "${NOTE} Config for $DIR1 not found, copying from assets."
        cp -r assets/$DIR1 ~/.config/ && echo "Copy $DIR1 completed!" || echo "Error: Failed to copy $DIR1 config files."
    fi
done

echo "-----"
printf "\n%.0s" {1..3}

# Clean up temporary directories.
# Remove temporary GTK themes and icons clone.
if [ -d "GTK-themes-icons" ]; then
    echo "$NOTE GTK themes and Icons directory exist..deleting..."
    rm -rf "GTK-themes-icons"
fi

echo "-----"
printf "\n%.0s" {1..3}

# Sync Hyprland-Dots into the home directory.
# Install Hyprland-Dots.
printf "$NOTE Downloading Hyprland-Dots to the home directory...\n"
if [ -d ~/Hyprland-Dots ]; then
    cd ~/Hyprland-Dots
    git stash
    git pull
    chmod +x copy.sh
    ./copy.sh
else
    if git clone --depth 1 https://github.com/JaKooLit/Hyprland-Dots ~/Hyprland-Dots; then
        cd ~/Hyprland-Dots || exit 1
        chmod +x copy.sh
        ./copy.sh
    else
        echo -e "$ERROR Failed to download Hyprland-Dots"
    fi
fi

#return to NixOS-Hyprland
cd ~/NixOS-Hyprland

# Install fastfetch assets when missing.
if [ ! -f "$HOME/.config/fastfetch/nixos.png" ]; then
    cp -r assets/fastfetch "$HOME/.config/"
fi

printf "\n%.0s" {1..2}

if command -v Hyprland &>/dev/null; then
    printf "\n${OK} Installation completed successfully.${RESET}\n"
    if type nhl_print_recovery_key_and_confirm >/dev/null 2>&1; then
        nhl_print_recovery_key_and_confirm
    fi
    sleep 2
    printf "\n${NOTE} You can start Hyprland by running: Hyprland${RESET}\n"
    printf "\n${NOTE} A reboot is recommended to finalize all changes.${RESET}\n\n"

    # Prompt user to reboot
    read -rp "${CAT} Would you like to reboot now? (y/n): ${RESET}" HYP

    if [[ "$HYP" =~ ^[Yy]$ ]]; then
        # If user confirms, reboot the system
        systemctl reboot
    else
        # Print a message if the user does not want to reboot
        echo "Reboot skipped."
    fi
else
    # Print error message if Hyprland is not installed
    printf "\n${WARN} Hyprland failed to install. Please check Install-Logs...${RESET}\n\n"
    exit 1
fi
