{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.power.batteryChargeLimit;
in {
  options.local.power.batteryChargeLimit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply battery charge thresholds on supported hardware.";
    };

    startThreshold = lib.mkOption {
      type = lib.types.int;
      default = 75;
      description = "Start charging threshold percentage.";
    };

    endThreshold = lib.mkOption {
      type = lib.types.int;
      default = 95;
      description = "Stop charging threshold percentage.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.startThreshold >= 0 && cfg.startThreshold <= 100;
        message = "local.power.batteryChargeLimit.startThreshold must be between 0 and 100.";
      }
      {
        assertion = cfg.endThreshold >= 0 && cfg.endThreshold <= 100;
        message = "local.power.batteryChargeLimit.endThreshold must be between 0 and 100.";
      }
      {
        assertion = cfg.startThreshold <= cfg.endThreshold;
        message = "local.power.batteryChargeLimit.startThreshold must be <= endThreshold.";
      }
    ];

    systemd.services.risiq-battery-charge-threshold = {
      description = "Apply battery charge threshold defaults";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -eu
        shopt -s nullglob
        for bat in /sys/class/power_supply/BAT*; do
          if [ -w "$bat/charge_control_start_threshold" ]; then
            echo ${toString cfg.startThreshold} > "$bat/charge_control_start_threshold"
          fi
          if [ -w "$bat/charge_control_end_threshold" ]; then
            echo ${toString cfg.endThreshold} > "$bat/charge_control_end_threshold"
          fi
        done
      '';
      path = [pkgs.bash];
    };
  };
}
