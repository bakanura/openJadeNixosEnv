{
  pkgs,
  lib,
  ...
}: let
  installVscodeExtensions = pkgs.writeShellScriptBin "vscode-install-extensions" ''
    set -euo pipefail

    code_bin=""
    if command -v code >/dev/null 2>&1; then
      code_bin="$(command -v code)"
    elif [ -x /run/current-system/sw/bin/code ]; then
      code_bin="/run/current-system/sw/bin/code"
    fi

    if [ -z "$code_bin" ]; then
      echo "[ERROR] VS Code CLI 'code' not found."
      echo "Open VS Code once or ensure it is installed and on PATH."
      exit 1
    fi

    extensions=(
      # Existing extensions detected on this system
      "betajob.modulestf"
      "cosmicnight.cosmic-night"
      "endormi.2077-theme"
      "pydemia.cobalt9"

      # Dev Containers / Docker / infra
      "ms-vscode-remote.remote-containers"
      "ms-vscode-remote.remote-ssh"
      "ms-azuretools.vscode-docker"
      "hashicorp.terraform"

      # Language and shell support
      "golang.go"
      "ms-vscode.powershell"
      "redhat.vscode-yaml"
      "tamasfe.even-better-toml"
      "ms-python.python"

      # UX and code quality
      "pkief.material-icon-theme"
      "eamodio.gitlens"
      "github.vscode-pull-request-github"
      "usernamehw.errorlens"
      "streetsidesoftware.code-spell-checker"
      "editorconfig.editorconfig"
    )

    installed="$("$code_bin" --list-extensions 2>/dev/null || true)"
    for ext in "''${extensions[@]}"; do
      if echo "$installed" | grep -qi "^$ext$"; then
        echo "[INFO] Already installed: $ext"
        continue
      fi
      echo "[INFO] Installing $ext"
      "$code_bin" --install-extension "$ext" --force || true
    done

    echo "[OK] Extension sync complete."
  '';

  listVscodeExtensions = pkgs.writeShellScriptBin "vscode-list-extensions" ''
    set -euo pipefail
    if ! command -v code >/dev/null 2>&1; then
      echo "[ERROR] VS Code CLI 'code' not found."
      exit 1
    fi
    code --list-extensions | sort
  '';
in {
  home.packages = [
    installVscodeExtensions
    listVscodeExtensions
  ];

  # Best-effort automatic extension sync on HM activation.
  # Run once in background so rebuild/switch does not block.
  home.activation.vscodeExtensionsAutoInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    marker="$HOME/.local/state/vscode-extensions-synced.done"
    mkdir -p "$HOME/.local/state"
    code_bin=""

    if command -v code >/dev/null 2>&1; then
      code_bin="$(command -v code)"
    elif [ -x /run/current-system/sw/bin/code ]; then
      code_bin="/run/current-system/sw/bin/code"
    fi

    # This repo is meant to stay local-first; remove the ChatGPT extension if it
    # was installed by an earlier activation.
    if [ -n "$code_bin" ]; then
      "$code_bin" --uninstall-extension openai.chatgpt --force >/dev/null 2>&1 || true
    fi

    if [ ! -f "$marker" ] && [ -n "$code_bin" ]; then
      # Avoid duplicate background workers across quick successive activations.
      if ! pgrep -f "vscode-install-extensions" >/dev/null 2>&1; then
        (
          timeout 900 ${installVscodeExtensions}/bin/vscode-install-extensions >/dev/null 2>&1 && touch "$marker"
        ) >/dev/null 2>&1 &
      fi
    fi
  '';
}
