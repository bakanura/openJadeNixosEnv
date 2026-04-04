{
  config,
  host,
  lib,
  pkgs,
  username,
  ...
}: let
  cfg = config.local.customUiTranslation;
  resolvedApiKeyFile =
    if cfg.encryptedApiKeyFile != null
    then cfg.decryptedApiKeyRuntimePath
    else cfg.apiKeyFile;
  helper = pkgs.writeShellApplication {
    name = "custom-ui-translate";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./translate.py} "$@"
    '';
  };
  bootstrapSecret = pkgs.writeShellApplication {
    name = "custom-ui-translation-bootstrap-secret";
    runtimeInputs = [pkgs.age pkgs.coreutils pkgs.openssh pkgs.ssh-to-age];
    text = ''
      set -eu

      host_name="''${1:-${host}}"
      repo_root="$PWD"
      plain_key_file="$HOME/.config/deepl-api-key"
      host_pubkey="/etc/ssh/ssh_host_ed25519_key.pub"
      secret_dir="$repo_root/secrets/$host_name"
      secret_file="$secret_dir/deepl-api-key.age"

      if [ ! -f "$plain_key_file" ]; then
        echo "Missing plaintext DeepL key at $plain_key_file" >&2
        exit 1
      fi

      if [ ! -f "$host_pubkey" ]; then
        echo "Missing SSH host public key at $host_pubkey" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/mkdir -p "$secret_dir"
      ${pkgs.coreutils}/bin/cp "$host_pubkey" "$secret_dir/ssh_host_ed25519_key.pub"

      recipient="$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$host_pubkey")"
      ${pkgs.age}/bin/age -r "$recipient" -o "$secret_file" "$plain_key_file"

      echo "Wrote encrypted DeepL key to $secret_file"
      echo "Host recipient recorded in $secret_dir/ssh_host_ed25519_key.pub"
    '';
  };
in {
  options.local.customUiTranslation = {
    enable = lib.mkEnableOption "shared translation helper for custom script-driven UI";

    provider = lib.mkOption {
      type = lib.types.enum ["deepl"];
      default = "deepl";
      description = "Translation backend used for custom UI helpers.";
    };

    sourceLanguage = lib.mkOption {
      type = lib.types.str;
      default = "EN";
      description = "Source language code for UI strings authored in the repo.";
    };

    targetLanguage = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Target language for custom UI translation, for example DE.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional file containing the DeepL API key for custom UI translation.";
    };

    encryptedApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional age-encrypted DeepL API key that is decrypted on the host at activation time.";
    };

    decryptedApiKeyRuntimePath = lib.mkOption {
      type = lib.types.str;
      default = "/run/custom-ui-translation/deepl-api-key";
      description = "Runtime path where an encrypted DeepL API key is decrypted for custom UI translation.";
    };

    secretIdentityFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "Private key used to decrypt the encrypted DeepL API key on the host.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Generated helper package for custom UI translation.";
    };
  };

  config = lib.mkIf cfg.enable {
    local.customUiTranslation.package = helper;

    environment.systemPackages = [
      helper
      bootstrapSecret
    ];

    systemd.tmpfiles.rules = lib.mkIf (cfg.encryptedApiKeyFile != null) [
      "d /run/custom-ui-translation 0750 root ${username} - -"
    ];

    systemd.services.custom-ui-translation-secret = lib.mkIf (cfg.encryptedApiKeyFile != null) {
      description = "Decrypt DeepL API key for custom UI translation";
      wantedBy = ["multi-user.target"];
      before = [
        "display-manager.service"
        "usbguard.service"
      ];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        runtime_dir="$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg cfg.decryptedApiKeyRuntimePath})"
        tmp_file="$(${pkgs.coreutils}/bin/mktemp)"

        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g ${username} "$runtime_dir"
        ${pkgs.age}/bin/age -d -i ${lib.escapeShellArg cfg.secretIdentityFile} -o "$tmp_file" ${cfg.encryptedApiKeyFile}
        ${pkgs.coreutils}/bin/install -m 0640 -o root -g ${username} "$tmp_file" ${lib.escapeShellArg cfg.decryptedApiKeyRuntimePath}
        ${pkgs.coreutils}/bin/rm -f "$tmp_file"
      '';
    };

    environment.sessionVariables =
      {
        CUSTOM_UI_TRANSLATION_ENABLE = "1";
        CUSTOM_UI_TRANSLATION_PROVIDER = cfg.provider;
        CUSTOM_UI_TRANSLATION_SOURCE_LANGUAGE = cfg.sourceLanguage;
        CUSTOM_UI_TRANSLATE_BIN = "${helper}/bin/custom-ui-translate";
      }
      // lib.optionalAttrs (cfg.targetLanguage != null) {
        CUSTOM_UI_TRANSLATION_TARGET_LANGUAGE = cfg.targetLanguage;
      }
      // lib.optionalAttrs (resolvedApiKeyFile != null) {
        CUSTOM_UI_TRANSLATION_API_KEY_FILE = toString resolvedApiKeyFile;
      };
  };
}
