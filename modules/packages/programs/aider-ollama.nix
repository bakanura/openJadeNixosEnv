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
  aiderBasePkg =
    if pkgsUnstable != null && builtins.hasAttr "aider-chat" pkgsUnstable
    then pkgsUnstable.aider-chat
    else pkgs.aider-chat;
  aiderPkg =
    aiderBasePkg.overrideAttrs
    (
      old: {
        doCheck = false;
        doInstallCheck = false;
        pytestCheckPhase = ":";
        installCheckPhase = ":";
        disabledTests =
          (old.disabledTests or [])
          ++ [
            "tests/basic/test_commands.py::TestCommands::test_cmd_read_only_with_image_file"
            "tests/basic/test_commands.py::TestCommands::test_cmd_tokens_output"
            "tests/basic/test_models.py::TestModels::test_max_context_tokens"
          ];
      }
    );
  rocmEnv = lib.optionalAttrs (config.drivers.amdgpu.enable or false) {
    HSA_OVERRIDE_GFX_VERSION = "11.0.3";
  };
in {
  nixpkgs.config.rocmSupport = config.drivers.amdgpu.enable or false;

  environment.systemPackages = [
    aiderPkg
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
