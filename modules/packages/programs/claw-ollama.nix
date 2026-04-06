{
  lib,
  pkgs,
  pkgsUnstable ? null,
  config,
  ...
}: let
  ollamaPkg =
    if pkgsUnstable != null && builtins.hasAttr "ollama-rocm" pkgsUnstable
    then pkgsUnstable.ollama-rocm
    else if builtins.hasAttr "ollama-rocm" pkgs
    then pkgs.ollama-rocm
    else pkgs.ollama;

  clawPkg = pkgs.callPackage ../../../pkgs/claw-code-local.nix {};

  clawLocalPkg = pkgs.symlinkJoin {
    name = "claw-code-local-only";
    paths = [clawPkg];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram "$out/bin/claw" \
        --run '
          if [ "$EUID" -ne 0 ]; then
            SUDO_BIN="/run/wrappers/bin/sudo"
            if [ ! -x "$SUDO_BIN" ]; then
              SUDO_BIN="${pkgs.sudo}/bin/sudo"
            fi

            "$SUDO_BIN" -K >/dev/null 2>&1 || true
            "$SUDO_BIN" -k >/dev/null 2>&1 || true
            "$SUDO_BIN" -v
            "$SUDO_BIN" -K >/dev/null 2>&1 || true
          fi
        ' \
        --set OPENAI_API_KEY ollama \
        --set OPENAI_BASE_URL http://127.0.0.1:11434/v1 \
        --unset ANTHROPIC_API_KEY \
        --unset ANTHROPIC_AUTH_TOKEN \
        --unset ANTHROPIC_BASE_URL \
        --unset GOOGLE_API_KEY \
        --unset OPENROUTER_API_KEY \
        --unset DEEPSEEK_API_KEY \
        --unset XAI_API_KEY \
        --unset GROQ_API_KEY \
        --unset MISTRAL_API_KEY
    '';
  };

  rocmEnv = lib.optionalAttrs (config.drivers.amdgpu.enable or false) {
    HSA_OVERRIDE_GFX_VERSION = "11.0.3";
  };
in {
  nixpkgs.config.rocmSupport = config.drivers.amdgpu.enable or false;

  environment.systemPackages = [
    clawLocalPkg
    ollamaPkg
  ];

  services.ollama =
    {
      enable = true;
      package = ollamaPkg;
      loadModels = ["qwen2.5-coder:7b"];
    }
    // lib.optionalAttrs (config.drivers.amdgpu.enable or false) {
      acceleration = "rocm";
      rocmOverrideGfx = "11.0.3";
    };

  systemd.services.ollama.environment = rocmEnv;
}
