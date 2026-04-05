{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    kitty
    wezterm
    (writeShellScriptBin "nhl-open-terminal" ''
      #!/usr/bin/env bash
      set -eu

      if command -v ghostty >/dev/null 2>&1; then
        exec ghostty "$@"
      fi

      if command -v kitty >/dev/null 2>&1; then
        exec kitty "$@"
      fi

      if command -v wezterm >/dev/null 2>&1; then
        exec wezterm start --always-new-process "$@"
      fi

      echo "No supported terminal found. Install ghostty, kitty, or wezterm." >&2
      exit 1
    '')
  ];
}
