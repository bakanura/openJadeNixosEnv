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

    # Allow fingerprint auth at local login (ly/login), while keeping password fallback.
    security.pam.services = {
      ly.fprintAuth = true;
      login.fprintAuth = true;
    };

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
