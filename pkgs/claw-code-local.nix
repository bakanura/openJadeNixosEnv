{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  perl,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "claw-code-local";
  version = "unstable-2026-04-06";

  src = fetchFromGitHub {
    owner = "codetwentyfive";
    repo = "claw-code-local";
    rev = "f4cc5d71808318a6cf7a64c3588d31b4a09fd752";
    hash = "sha256-0wvq6lNm6XbDPTzeUvwRjZlx+VWNZdPmQ4dCBQl+SuA=";
  };

  sourceRoot = "source/rust";
  cargoHash = "sha256-gbkct9v8CMY9gy2gwM4sBOUilc4peZLdBbfkjiCB1yc=";

  nativeBuildInputs = [
    pkg-config
    perl
  ];

  buildInputs = [
    openssl
  ];

  buildAndTestSubdir = ".";
  cargoBuildFlags = ["-p" "rusty-claude-cli"];
  doCheck = false;

  meta = with lib; {
    description = "Local-first Claw Code fork for Ollama and OpenAI-compatible endpoints";
    homepage = "https://github.com/codetwentyfive/claw-code-local";
    license = licenses.mit;
    mainProgram = "claw";
    platforms = platforms.linux;
  };
}
