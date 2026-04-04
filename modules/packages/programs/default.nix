{
  pkgs,
  pkgsUnstable ? null,
  ...
}:
let
  onePasswordSource =
    if pkgsUnstable != null then pkgsUnstable else pkgs;
  onePasswordGuiPkg =
    if builtins.hasAttr "_1password-gui-beta" onePasswordSource then
      onePasswordSource._1password-gui-beta
    else if builtins.hasAttr "_1password-gui" onePasswordSource then
      onePasswordSource._1password-gui
    else if builtins.hasAttr "_1password-gui-beta" pkgs then
      pkgs._1password-gui-beta
    else
      pkgs._1password-gui;
in {
  services.power-profiles-daemon.enable = true;

  programs = {
    hyprland = {
      enable = true;
      withUWSM = false;
      #package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland; #hyprland-git
      #portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland; #xdph-git

      portalPackage = pkgs.xdg-desktop-portal-hyprland; # xdph none git
      xwayland.enable = true;
    };
    zsh.enable = true;
    firefox.enable = false;
    waybar.enable = false; #started by Hyprland dotfiles. Enabling causes two waybars
    hyprlock.enable = true;
    dconf.enable = true;
    seahorse.enable = true;
    fuse.userAllowOther = true;
    mtr.enable = true;
    gamemode.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    git.enable = true;
    tmux.enable = true;
    nm-applet.indicator = true;
    neovim = {
      enable = true;
      defaultEditor = false;
    };

    thunar.enable = true;
    thunar.plugins = with pkgs; [
      xfce.exo
      xfce.mousepad
      xfce.thunar-archive-plugin
      xfce.thunar-volman
      xfce.tumbler
    ];

    _1password-gui = {
      enable = true;
      package = onePasswordGuiPkg;
      polkitPolicyOwners = [ "roederp" ];
    };
  };

  nixpkgs.config.allowUnfree = true;
}
