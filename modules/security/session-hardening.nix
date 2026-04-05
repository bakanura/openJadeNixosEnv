{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.security.session;
in {
  options.local.security.session = {
    enable = lib.mkEnableOption "session hardening for login, power actions, and lock fail-safe handling";
    powerButtonUseAcpid = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Handle the physical power button through acpid instead of logind so USB HID consumer-control devices cannot trigger the same action.";
    };
    powerButtonAction = lib.mkOption {
      type = lib.types.enum ["ignore" "poweroff" "reboot" "halt" "kexec" "suspend" "hibernate" "hybrid-sleep" "lock"];
      default = "poweroff";
      description = "logind action to perform when the built-in power button is pressed.";
    };
    rebootButtonAction = lib.mkOption {
      type = lib.types.enum ["ignore" "poweroff" "reboot" "halt" "kexec" "suspend" "hibernate" "hybrid-sleep" "lock"];
      default = "reboot";
      description = "logind action to perform when a reboot key event is received.";
    };
  };

  config = lib.mkMerge [
    {
      local.security.session.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # Keep sleep targets enabled and explicit so suspend/hibernate actions are available.
      systemd.sleep.extraConfig = ''
        AllowSuspend=yes
        AllowHibernation=yes
        AllowSuspendThenHibernate=yes
        AllowHybridSleep=yes
      '';

      # Keep logind defaults explicit and predictable for laptop behavior.
      services.logind = {
        settings.Login = {
          HandleLidSwitch = "ignore";
          HandleLidSwitchDocked = "ignore";
          HandleLidSwitchExternalPower = "ignore";
          HandlePowerKey =
            if cfg.powerButtonUseAcpid
            then "ignore"
            else cfg.powerButtonAction;
          HandleSuspendKey = "suspend";
          HandleHibernateKey = "hibernate";
          HandleRebootKey = cfg.rebootButtonAction;
        };
      };

      services.acpid = lib.mkIf cfg.powerButtonUseAcpid {
        enable = true;
        powerEventCommands = ''
          ${pkgs.systemd}/bin/systemctl ${cfg.powerButtonAction}
        '';
      };

      # Authorize active local users for common power/session actions from menus.
      security.polkit.extraConfig = lib.mkAfter ''
        polkit.addRule(function(action, subject) {
          if (
            subject.isInGroup("users") &&
            (
              action.id == "org.freedesktop.login1.reboot" ||
              action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
              action.id == "org.freedesktop.login1.power-off" ||
              action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
              action.id == "org.freedesktop.login1.suspend" ||
              action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
              action.id == "org.freedesktop.login1.hibernate" ||
              action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
              action.id == "org.freedesktop.login1.hybrid-sleep" ||
              action.id == "org.freedesktop.login1.hybrid-sleep-multiple-sessions" ||
              action.id == "org.freedesktop.login1.suspend-then-hibernate" ||
              action.id == "org.freedesktop.login1.suspend-then-hibernate-multiple-sessions"
            )
          ) {
            return polkit.Result.YES;
          }
        });
      '';

      # Fail closed: if a running hyprlock process exits while session is still
      # marked as locked, terminate the user session so a fresh login is required.
      systemd.user.services.nhl-lockscreen-watchdog = {
        description = "RISIQ lockscreen watchdog";
        after = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2s";
          ExecStart = "${pkgs.writeShellScript "nhl-lockscreen-watchdog" ''
            set -eu

            # The service runs for the active user session and monitors hyprlock.
            while true; do
              if pgrep -x hyprlock >/dev/null 2>&1; then
                # A lock process exists; wait for it to stop.
                while pgrep -x hyprlock >/dev/null 2>&1; do
                  sleep 1
                done

                # Give logind one moment to update lock state.
                sleep 1

                session_id="''${XDG_SESSION_ID:-}"
                if [ -n "$session_id" ]; then
                  locked="$(loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null || true)"
                  if [ "$locked" = "yes" ]; then
                    logger -t nhl-lockscreen-watchdog "hyprlock exited while session remained locked; terminating session $session_id"
                    exec loginctl terminate-session "$session_id"
                  fi
                fi
              fi

              sleep 1
            done
          ''}";
        };
      };
    })
  ];
}
