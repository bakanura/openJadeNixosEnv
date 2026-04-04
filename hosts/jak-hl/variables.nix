# Project source: https://github.com/JaKooLit/NixOS-Hyprland
# Define host-specific variables.
{
  # Git Configuration ( For Pulling Software Repos )
  gitUsername = "JaKooLit";
  gitEmail = "ejhay.games@gmail.com";

  # Hyprland Settings
  extraMonitorSettings = "";

  # Waybar Settings
  clock24h = true;

  # Configure default applications.
  browser = "firefox"; # Set the default browser (use google-chrome-stable for Google Chrome).
  terminal = "nhl-open-terminal"; # Stable launcher that falls back across installed terminals.
  keyboardLayout = "us";
}
