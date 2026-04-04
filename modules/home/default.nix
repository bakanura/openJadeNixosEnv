{...}: {
  imports = [
    ./terminals/tmux.nix
    ./terminals/ghostty.nix
    ./editors/nixvim.nix
    ./cli/bat.nix
    ./cli/btop.nix
    ./cli/bottom.nix
    ./cli/eza.nix
    ./cli/fzf.nix
    ./cli/git
    ./cli/htop.nix
    ./cli/tealdeer.nix
    ./vscode
    ./yazi
    ./overview.nix
    ./hypr-fixes.nix
    ./edge-apps.nix
    ./default-browser.nix
    ./first-login-setup.nix
  ];
}
