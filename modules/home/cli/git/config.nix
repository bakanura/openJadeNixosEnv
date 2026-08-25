{
  hostVars,
  lib,
  pkgs,
  ...
}: let
  inherit (hostVars) gitEmail gitUsername;

  gitBin = lib.getExe pkgs.git;
  ghBin = lib.getExe pkgs.gh;
  risiqConfigPath = "$HOME/.config/git/identities/risiq.de.inc";
  bakaConfigPath = "$HOME/.config/git/identities/baka.inc";
in {
  programs.git = {
    enable = true;
    signing.format = "openpgp";

    settings = {
      user = {
        name = gitUsername;
        email = gitEmail;
      };
      push.default = "simple";
      credential.helper = "cache --timeout=7200";
      init.defaultBranch = "main";
      log.decorate = "full";
      log.date = "iso";
      merge.conflictStyle = "diff3";
      core.editor = "nvim";
      diff.colorMoved = "default";
      merge.stat = "true";
      core.whitespace = "fix,-indent-with-non-tab,trailing-space,cr-at-eol";

      alias = {
        br = "branch --sort=-committerdate";
        co = "checkout";
        af = "!git add $(git ls-files -m -o --exclude-standard | fzf -m)";
        com = "commit -a";
        ca = "commit -a";
        df = "diff";
        gs = "stash";
        gp = "pull";
        st = "status";
        lg = "log --graph --pretty=format:'%Cred%h%Creset - %C(yellow)%d%Creset %s %C(green)(%cr)%C(bold blue) <%an>%Creset' --abbrev-commit";
        edit-unmerged = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; hx `f`";
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      true-color = "never";

      features = "unobtrusive-line-numbers decorations";
      unobtrusive-line-numbers = {
        line-numbers = true;
        line-numbers-left-format = "{nm:>4}│";
        line-numbers-right-format = "{np:>4}│";
        line-numbers-left-style = "grey";
        line-numbers-right-style = "grey";
      };
      decorations = {
        commit-decoration-style = "bold grey box ul";
        file-style = "bold blue";
        file-decoration-style = "ul";
        hunk-header-decoration-style = "box";
      };
    };
  };

  home.packages = [
    (pkgs.writeShellScriptBin "git-risiq" ''
      #!/usr/bin/env bash
      set -euo pipefail

      ensure_gh_auth() {
        local host="$1"

        if ! ${ghBin} auth status --hostname "$host" >/dev/null 2>&1; then
          exec ${ghBin} auth login --hostname "$host" --git-protocol ssh --web
        fi
      }

      if [ "''${1-}" = "clone" ]; then
        ensure_gh_auth "risiq.ghe.com"
        exec ${gitBin} clone -c include.path="${risiqConfigPath}" "''${@:2}"
      fi

      exec ${gitBin} "$@"
    '')
    (pkgs.writeShellScriptBin "baka" ''
      #!/usr/bin/env bash
      set -euo pipefail

      ensure_gh_auth() {
        local host="$1"

        if ! ${ghBin} auth status --hostname "$host" >/dev/null 2>&1; then
          exec ${ghBin} auth login --hostname "$host" --git-protocol ssh --web
        fi
      }

      if [ "$#" -eq 0 ]; then
        exec ${gitBin} -c include.path="${bakaConfigPath}"
      fi

      if [ "$1" = "clone" ]; then
        ensure_gh_auth "github.com"
        exec ${gitBin} clone -c include.path="${bakaConfigPath}" "''${@:2}"
      fi

      exec ${gitBin} -c include.path="${bakaConfigPath}" "$@"
    '')
  ];

  home.shellAliases = {
    git = "git-risiq";
  };
}
