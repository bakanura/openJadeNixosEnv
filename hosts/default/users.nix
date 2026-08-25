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
      initialPassword = lib.mkIf (username == "openJade-bootstrap") "risiq1234";
      extraGroups = [
        "networkmanager"
        "wheel"
        "libvirtd"
        "scanner"
        "lp"
        "video"
        "input"
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
      # Enable zsh plugins via NixOS module options
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };
  };
}
