# Project source: https://github.com/JaKooLit/NixOS-Hyprland
# Define host-specific variables.
{
  # Git Configuration ( For Pulling Software Repos )
  gitUsername = "Phil Roeder";
  gitEmail = "phil.roeder@rsiq.de";

  # Hyprland Settings
  extraMonitorSettings = "";

  # Waybar Settings
  clock24h = true;

  # Configure default applications.
  browser = "firefox"; # Set the default browser (use google-chrome-stable for Google Chrome).
  terminal = "nhl-open-terminal"; # Stable launcher that falls back across installed terminals.
  keyboardLayout = "de";
  vscodeGitConfirmSync = true; # true keeps the VS Code sync confirmation prompt.
}
