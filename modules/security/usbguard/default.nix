{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  cfg = config.local.security.usb;
  translationCfg = config.local.customUiTranslation;
  whitelist = builtins.fromJSON (builtins.readFile ./whitelist.json);
  whitelistRules = map (device: device.rule) whitelist.devices;
  repoWhitelistRulesText = lib.concatLines whitelistRules;
  usbguardReviewGo = pkgs.buildGoModule {
    pname = "usbguard-review-queue";
    version = "0.1.0";
    src = lib.cleanSource ./go-review;
    vendorHash = null;
    ldflags = ["-s" "-w"];
    nativeBuildInputs = [pkgs.makeWrapper];
    postFixup = ''
      wrapProgram "$out/bin/usbguard-review-queue" \
        --prefix PATH : "${lib.makeBinPath ([
          pkgs.usbguard
          pkgs.usbutils
          pkgs.libnotify
          pkgs.yad
        ] ++ lib.optional translationCfg.enable translationCfg.package)}"
    '';
  };
  usbguardControl = pkgs.writeShellApplication {
    name = "usb-guard";
    runtimeInputs = [usbguardReviewGo];
    text = ''
      exec ${usbguardReviewGo}/bin/usbguard-review-queue "$@"
    '';
  };
  usbguardReviewCleanup = pkgs.writeShellScript "usbguard-review-cleanup" ''
    set +e
    ${pkgs.procps}/bin/pkill -KILL -u "${username}" -f "yad.*USBGuard" >/dev/null 2>&1
    ${pkgs.procps}/bin/pkill -KILL -u "${username}" -f "yad.*Confirm permanent approval" >/dev/null 2>&1
    ${pkgs.procps}/bin/pkill -KILL -u "${username}" -f "usbguard-review-queue" >/dev/null 2>&1
    ${pkgs.procps}/bin/pkill -KILL -u "${username}" -f "usb-guard --watch" >/dev/null 2>&1
    exit 0
  '';
in {
  options.local.security.usb = {
    enable = lib.mkEnableOption "USB hardening against rogue devices and HID-triggered abuse";

    review.enable = lib.mkEnableOption "queued review prompts for blocked USB devices";

    review.autoBlockStorage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Quarantine newly seen USB storage devices into the persistent block list instead of showing the normal approval popup.";
    };

    requireAuthForPowerActions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require an authentication prompt for shutdown and reboot actions so injected keystrokes cannot silently power off the machine.";
    };

    notifyUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show graphical review prompts for newly blocked USB devices in graphical sessions.";
    };
  };

  config = lib.mkMerge [
    {
      local.security.usb.enable = lib.mkDefault true;
      local.security.usb.review.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      services.usbguard = {
        enable = true;
        dbus.enable = true;
        IPCAllowedUsers = ["root" username];
        IPCAllowedGroups = ["wheel"];
        implicitPolicyTarget = "block";
        presentControllerPolicy = "keep";
        presentDevicePolicy = "apply-policy";
        insertedDevicePolicy = "block";
        restoreControllerDeviceState = true;
      };

      systemd.services.usbguard.preStart = lib.mkBefore ''
        whitelist_file=${pkgs.writeText "usbguard-whitelist-rules" repoWhitelistRulesText}
        rules_file=/var/lib/usbguard/rules.conf
        dynamic_builtins_file="$(${pkgs.coreutils}/bin/mktemp)"
        filtered_rules_file="$(${pkgs.coreutils}/bin/mktemp)"

        [ -f "$rules_file" ] || ${pkgs.coreutils}/bin/touch "$rules_file"

        ${pkgs.usbguard}/bin/usbguard generate-policy | ${pkgs.gawk}/bin/awk '/with-connect-type "hardwired"/ { print }' > "$dynamic_builtins_file"

        ${pkgs.gawk}/bin/awk '
          function field_value(line, key,    pattern, arr) {
            pattern = key " \"[^\"]*\"|" key " [^ ]+"
            if (match(line, pattern)) {
              split(substr(line, RSTART, RLENGTH), arr, " ")
              return arr[2]
            }
            return ""
          }
          FNR == NR {
            id = field_value($0, "id")
            port = field_value($0, "via-port")
            if (id != "" && port != "") {
              managed[id SUBSEP port] = 1
            }
            next
          }
          {
            id = field_value($0, "id")
            port = field_value($0, "via-port")
            if (id != "" && port != "" && ((id SUBSEP port) in managed)) {
              next
            }
            print
          }
        ' "$whitelist_file" "$rules_file" > "$filtered_rules_file"

        tmp_rules="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/cat "$dynamic_builtins_file" "$whitelist_file" "$filtered_rules_file" | ${pkgs.gawk}/bin/awk 'NF && !seen[$0]++' > "$tmp_rules"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp_rules" "$rules_file"
        ${pkgs.coreutils}/bin/rm -f "$dynamic_builtins_file"
        ${pkgs.coreutils}/bin/rm -f "$filtered_rules_file"
        ${pkgs.coreutils}/bin/rm -f "$tmp_rules"
      '';

      environment.systemPackages = [
        pkgs.usbguard
        usbguardControl
        usbguardReviewGo
      ];

      security.polkit.extraConfig = lib.mkBefore (
        lib.optionalString cfg.requireAuthForPowerActions ''
          polkit.addRule(function(action, subject) {
            if (
              subject.isInGroup("users") &&
              (
                action.id == "org.freedesktop.login1.reboot" ||
                action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
                action.id == "org.freedesktop.login1.power-off" ||
                action.id == "org.freedesktop.login1.power-off-multiple-sessions"
              )
            ) {
              return polkit.Result.AUTH_SELF_KEEP;
            }
          });
        ''
      );

      systemd.user.services.nhl-usbguard-review = lib.mkIf cfg.review.enable {
        description = "RISIQ USBGuard review queue";
        after = ["default.target"];
        wantedBy = ["default.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          TimeoutStopSec = "5s";
          KillMode = "control-group";
          SendSIGKILL = true;
          Nice = 10;
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
          ExecStopPost = "${usbguardReviewCleanup}";
          Environment =
            [
              "USBGUARD_WHITELIST_JSON=${./whitelist.json}"
              "USBGUARD_MAX_BLOCKED_SCAN=64"
              "USBGUARD_MAX_PROMPTS_PER_CYCLE=1"
              "USBGUARD_PROMPT_COOLDOWN_SECONDS=2"
              "USBGUARD_PORT_PROMPT_COOLDOWN_SECONDS=15"
              "USBGUARD_LSUSB_TIMEOUT_SECONDS=2.5"
              "USBGUARD_SERIAL_QUEUE_MODE=1"
              "USBGUARD_DISABLE_DOCK_GROUPING=0"
              "USBGUARD_QUEUE_POLL_SECONDS=2"
              "USBGUARD_QUEUE_DORMANT_BACKLOG=12"
              "USBGUARD_QUEUE_DORMANT_SLEEP_SECONDS=4"
              "USBGUARD_REVIEW_AUTO_PROMPT=1"
              "USBGUARD_REVIEW_AUTO_BLOCK_STORAGE=${if cfg.review.autoBlockStorage then "1" else "0"}"
              "USBGUARD_REVIEW_POPUPS=${if cfg.notifyUser then "1" else "0"}"
              "CUSTOM_UI_TRANSLATION_ENABLE=${if translationCfg.enable then "1" else "0"}"
              "CUSTOM_UI_TRANSLATION_PROVIDER=${translationCfg.provider}"
              "CUSTOM_UI_TRANSLATION_SOURCE_LANGUAGE=${translationCfg.sourceLanguage}"
              "CUSTOM_UI_TRANSLATE_BIN=${translationCfg.package}/bin/custom-ui-translate"
            ]
            ++ lib.optional (translationCfg.targetLanguage != null) "CUSTOM_UI_TRANSLATION_TARGET_LANGUAGE=${translationCfg.targetLanguage}"
            ++ lib.optional (translationCfg.apiKeyFile != null) "CUSTOM_UI_TRANSLATION_API_KEY_FILE=${toString translationCfg.apiKeyFile}";
          ExecStart = "${usbguardControl}/bin/usb-guard --watch";
        };
      };
    })
  ];
}
