# Project source: https://github.com/JaKooLit/NixOS-Hyprland
# Configure user account settings and user-scoped packages.
{
  lib,
  pkgs,
  username,
  ...
}: let
  inherit (import ./variables.nix) gitUsername;
in {
  users = {
    mutableUsers = true;
    users."${username}" = {
      homeMode = "755";
      isNormalUser = true;
      description = "${gitUsername}";
      initialPassword = lib.mkIf (username == "risiq-bootstrap") "risiq1234";
      extraGroups = [
        "networkmanager"
        "wheel"
        "libvirtd"
        "scanner"
        "lp"
        "video"
        "input"
        "render"
        "usbguard"
        "audio"
      ];

      # define user packages here
      packages = with pkgs; [
      ];
    };

    defaultUserShell = pkgs.zsh;
  };

  environment.shells = with pkgs; [zsh];
  environment.systemPackages = with pkgs; [lsd fzf git];
  programs = {
    zsh = {
      ohMyZsh = {
        enable = true;
        theme = "agnoster";
        plugins = ["git"];
      };
      shellAliases = {
        code = "${pkgs.vscode}/bin/code 2> >(grep -v -E \"^(Warning: '(ozone-platform-hint|enable-features|enable-wayland-ime|wayland-text-input-version)' is not in the list of known options, but still passed to Electron/Chromium\\.)$\" >&2)";
      };
      # Enable zsh plugins via NixOS module options
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };
  };
}
