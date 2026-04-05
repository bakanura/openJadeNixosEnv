{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.power.fanCurve;

  defaultStrategies = {
    quiet = {
      fanSpeedUpdateFrequency = 10;
      movingAverageInterval = 90;
      speedCurve = [
        {
          temp = 0;
          speed = 0;
        }
        {
          temp = 48;
          speed = 0;
        }
        {
          temp = 58;
          speed = 18;
        }
        {
          temp = 66;
          speed = 24;
        }
        {
          temp = 74;
          speed = 34;
        }
        {
          temp = 82;
          speed = 48;
        }
        {
          temp = 88;
          speed = 65;
        }
        {
          temp = 94;
          speed = 100;
        }
      ];
    };

    balanced = {
      fanSpeedUpdateFrequency = 8;
      movingAverageInterval = 70;
      speedCurve = [
        {
          temp = 0;
          speed = 20;
        }
        {
          temp = 55;
          speed = 20;
        }
        {
          temp = 64;
          speed = 28;
        }
        {
          temp = 72;
          speed = 38;
        }
        {
          temp = 80;
          speed = 52;
        }
        {
          temp = 86;
          speed = 72;
        }
        {
          temp = 92;
          speed = 100;
        }
      ];
    };

    cooling = {
      fanSpeedUpdateFrequency = 5;
      movingAverageInterval = 40;
      speedCurve = [
        {
          temp = 0;
          speed = 28;
        }
        {
          temp = 50;
          speed = 28;
        }
        {
          temp = 60;
          speed = 36;
        }
        {
          temp = 68;
          speed = 46;
        }
        {
          temp = 76;
          speed = 60;
        }
        {
          temp = 84;
          speed = 78;
        }
        {
          temp = 90;
          speed = 100;
        }
      ];
    };
  };

  configJson = builtins.toJSON {
    "$schema" = "./config.schema.json";
    defaultStrategy = cfg.defaultStrategy;
    strategyOnDischarging = cfg.strategyOnDischarging;
    strategies = cfg.strategies;
  };
in {
  options.local.power.fanCurve = {
    enable = lib.mkEnableOption "Framework fan control with configurable temperature curves";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fw-fanctrl;
      description = "The fw-fanctrl package to use for Framework fan control.";
    };

    defaultStrategy = lib.mkOption {
      type = lib.types.str;
      default = "quiet";
      description = "The fw-fanctrl strategy used by default on AC power.";
    };

    strategyOnDischarging = lib.mkOption {
      type = lib.types.str;
      default = "quiet";
      description = "The fw-fanctrl strategy used on battery power.";
    };

    strategies = lib.mkOption {
      type = lib.types.attrs;
      default = defaultStrategies;
      description = "Strategy definitions written to /etc/fw-fanctrl/config.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.defaultStrategy cfg.strategies;
        message = "local.power.fanCurve.defaultStrategy must exist in local.power.fanCurve.strategies.";
      }
      {
        assertion =
          cfg.strategyOnDischarging
          == ""
          || builtins.hasAttr cfg.strategyOnDischarging cfg.strategies;
        message = "local.power.fanCurve.strategyOnDischarging must be empty or exist in local.power.fanCurve.strategies.";
      }
    ];

    environment.etc."fw-fanctrl/config.json".text = configJson;
    environment.etc."systemd/system-sleep/fw-fanctrl-suspend".source = "${cfg.package}/share/fw-fanctrl/fw-fanctrl-suspend";

    environment.systemPackages = [
      cfg.package
      (pkgs.writeShellScriptBin "fan-profile" ''
        set -euo pipefail

        if [ "$#" -eq 0 ]; then
          exec ${lib.getExe cfg.package} print current
        fi

        case "$1" in
          list)
            exec ${lib.getExe cfg.package} print list
            ;;
          current)
            exec ${lib.getExe cfg.package} print current
            ;;
          speed)
            exec ${lib.getExe cfg.package} print speed
            ;;
          *)
            exec ${lib.getExe cfg.package} use "$1"
            ;;
        esac
      '')
      (pkgs.writeShellScriptBin "fan-profile-cycle" ''
        set -euo pipefail

        current="$(${lib.getExe cfg.package} print current | tr -d '\n' | tr -d '\r')"
        case "$current" in
          cooling) next="balanced" ;;
          balanced) next="quiet" ;;
          quiet) next="quiet" ;;
          *) next="quiet" ;;
        esac

        ${lib.getExe cfg.package} use "$next" >/dev/null
        ${pkgs.libnotify}/bin/notify-send "Fan profile" "Switched to $next"
      '')
      (pkgs.writeShellScriptBin "fan-profile-step-up" ''
        set -euo pipefail

        current="$(${lib.getExe cfg.package} print current | tr -d '\n' | tr -d '\r')"
        case "$current" in
          quiet) next="balanced" ;;
          balanced) next="cooling" ;;
          cooling) next="cooling" ;;
          *) next="balanced" ;;
        esac

        ${lib.getExe cfg.package} use "$next" >/dev/null
        ${pkgs.libnotify}/bin/notify-send "Fan profile" "Switched to $next"
      '')
      (pkgs.writeShellScriptBin "fan-profile-toggle" ''
        set -euo pipefail

        current="$(${lib.getExe cfg.package} print current | tr -d '\n' | tr -d '\r')"
        case "$current" in
          cooling) next="quiet" ;;
          quiet) next="cooling" ;;
          balanced) next="cooling" ;;
          *) next="quiet" ;;
        esac

        ${lib.getExe cfg.package} use "$next" >/dev/null
        ${pkgs.libnotify}/bin/notify-send "Fan profile" "Toggled to $next"
      '')
    ];

    systemd.services.risiq-framework-fan-curve = {
      description = "Framework fan control service";
      wantedBy = ["multi-user.target"];
      after = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
        ExecStart = "${lib.getExe cfg.package} run --config /etc/fw-fanctrl/config.json --silent ${cfg.defaultStrategy}";
      };
    };
  };
}
