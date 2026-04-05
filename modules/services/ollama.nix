{
  pkgs,
  config,
  pkgsUnstable ? null,
  ...
}:
let
  ollamaPkg =
    if pkgsUnstable != null then pkgsUnstable.ollama-rocm
    else pkgs.ollama-rocm;
in {
  nixpkgs.config.rocmSupport = true;

  environment.systemPackages = with pkgs; [
    ollamaPkg
  ];

  services.ollama = {
    enable = true;
    package = ollamaPkg;
    acceleration = "rocm";
    loadModels = [ "qwen2.5-coder:7b" ];

    # Only keep this if plain ROCm still falls back to CPU
    rocmOverrideGfx = "11.0.3";
  };
}
