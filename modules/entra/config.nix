{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.entra;
  legacy = config.local.intune;
  managedEnabled = cfg.enable || legacy.enable;
  managedNonInteractive =
    if cfg.enable
    then cfg.nonInteractive
    else legacy.nonInteractive;
  managedDeviceId =
    if cfg.enable
    then cfg.deviceId
    else legacy.deviceId;
  installPortal =
    if cfg.enable
    then cfg.installPortal
    else legacy.installPortal;
  installBroker =
    if cfg.enable
    then cfg.installBroker
    else legacy.installBroker;
  installEdge =
    if cfg.enable
    then cfg.installEdge
    else legacy.installEdge;
in {
  options = {
    local.entra = {
      enable = lib.mkEnableOption "Microsoft Entra / Intune managed deployment mode";

      nonInteractive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run installer-related workflows in non-interactive mode for managed deployments.";
      };

      deviceId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional managed-device identifier exposed to installer scripts.";
      };

      installPortal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Microsoft Intune Portal client package.";
      };

      installBroker = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Microsoft Identity Broker for Entra/Intune sign-in.";
      };

      installEdge = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Microsoft Edge for Conditional Access and company resources.";
      };
    };

    # Backward-compatible option set.
    local.intune = {
      enable = lib.mkEnableOption "legacy Intune managed deployment mode alias";

      nonInteractive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Legacy alias for local.entra.nonInteractive.";
      };

      deviceId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Legacy alias for local.entra.deviceId.";
      };

      installPortal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Legacy alias for local.entra.installPortal.";
      };

      installBroker = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Legacy alias for local.entra.installBroker.";
      };

      installEdge = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Legacy alias for local.entra.installEdge.";
      };
    };
  };

  config = lib.mkIf managedEnabled {
    environment.etc."risiq/entra-managed".text = "true\n";
    environment.etc."risiq/entra/managed.conf".text = ''
      enabled=true
      non_interactive=${
        if managedNonInteractive
        then "true"
        else "false"
      }
      device_id=${managedDeviceId}
    '';

    environment.sessionVariables = {
      # Preferred variable names.
      ENTRA_MANAGED = "1";
      ENTRA_DEVICE_ID = managedDeviceId;
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";

      # Compatibility variables used by existing installer logic.
      INTUNE_MANAGED = "1";
      INTUNE_DEVICE_ID = managedDeviceId;
    };

    environment.systemPackages =
      [
        (pkgs.writeShellScriptBin "entra-status" ''
          set -euo pipefail
          echo "ENTRA_MANAGED=''${ENTRA_MANAGED:-0}"
          echo "ENTRA_NONINTERACTIVE=${
            if managedNonInteractive
            then "1"
            else "0"
          }"
          echo "ENTRA_DEVICE_ID=''${ENTRA_DEVICE_ID:-}"
          echo "INTUNE_MANAGED=''${INTUNE_MANAGED:-0}"
          echo "NHL_NONINTERACTIVE=${
            if managedNonInteractive
            then "1"
            else "0"
          }"
          echo "INTUNE_DEVICE_ID=''${INTUNE_DEVICE_ID:-}"
          if [ -f /etc/risiq/entra-managed ]; then
            echo "Marker: /etc/risiq/entra-managed present"
          else
            echo "Marker: /etc/risiq/entra-managed missing"
          fi
        '')
        (pkgs.writeShellScriptBin "entra-enroll" ''
          set -euo pipefail
          echo "Launching Microsoft Intune Portal enrollment..."
          exec intune-portal
        '')
        (pkgs.writeShellScriptBin "intune-status" ''
          exec ${pkgs.bash}/bin/bash -lc 'entra-status'
        '')
        (pkgs.writeShellScriptBin "intune-enroll" ''
          exec ${pkgs.bash}/bin/bash -lc 'entra-enroll'
        '')
        (pkgs.writeShellScriptBin "intune-portal-interactive" ''
          exec ${pkgs.intune-portal}/bin/intune-portal --interactive "$@"
        '')
      ]
      ++ lib.optionals installPortal [pkgs.intune-portal]
      ++ lib.optionals installBroker [pkgs.microsoft-identity-broker]
      ++ lib.optionals installEdge [pkgs.microsoft-edge];

    systemd.packages =
      lib.optionals installPortal [pkgs.intune-portal]
      ++ lib.optionals installBroker [pkgs.microsoft-identity-broker];
    systemd.tmpfiles.packages = lib.optionals installPortal [pkgs.intune-portal];

    # Use the vendor-provided system socket/service instead of a user unit.
    # The daemon expects socket activation on /run/intune/daemon.socket.
    systemd.sockets.intune-daemon.wantedBy = lib.mkIf installPortal ["sockets.target"];
  };
}
