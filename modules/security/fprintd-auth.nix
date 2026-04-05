{
  config,
  lib,
  ...
}: let
  cfg = config.local.security.fingerprint;
in {
  options.local.security.fingerprint = {
    enable = lib.mkEnableOption "fingerprint login via fprintd and PAM";
  };

  config = lib.mkIf cfg.enable {
    services.fprintd.enable = true;

    # Allow fingerprint auth at local login and lock screens, while keeping
    # password fallback available.
    security.pam.services = {
      hyprlock.fprintAuth = true;
      ly.fprintAuth = true;
      login.fprintAuth = true;
      swaylock.fprintAuth = true;
    };

    # Some fingerprint readers fail to recover after suspend/hibernate and PAM
    # silently falls back to password-only auth until fprintd is restarted.
    environment.etc."systemd/system-sleep/restart-fprintd".text = ''
      #!/bin/sh
      set -eu

      case "$1" in
        post)
          ${lib.getExe' config.systemd.package "systemctl"} try-restart fprintd.service >/dev/null 2>&1 || true
          ;;
      esac
    '';
    environment.etc."systemd/system-sleep/restart-fprintd".mode = "0755";

    # Authorize active local users to enroll their own fingerprints without
    # failing on Polkit permission checks from first-login flow.
    security.polkit.extraConfig = lib.mkAfter ''
      polkit.addRule(function(action, subject) {
        if (
          action.id == "net.reactivated.fprint.device.enroll" &&
          subject.active &&
          subject.local
        ) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
