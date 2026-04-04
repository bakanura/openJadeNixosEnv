# Project source: https://github.com/JaKooLit/NixOS-Hyprland
{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.drivers.amdgpu;
in {
  options.drivers.amdgpu = {
    enable = mkEnableOption "Enable AMD Drivers";
    displaylink.enable = mkEnableOption "Enable DisplayLink/evdi support for AMD hosts";
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = ["L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"];
    services.xserver.videoDrivers =
      ["amdgpu" "modesetting"]
      ++ lib.optional cfg.displaylink.enable "displaylink";

    # OpenGL
    hardware.graphics = {
      extraPackages = with pkgs; [
        libva
        libva-utils
      ];
    };
  };
}
