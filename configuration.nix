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

  services.ollama = import ./modules/services/ollama.nix {
    inherit pkgs config pkgsUnstable;
  };
}
