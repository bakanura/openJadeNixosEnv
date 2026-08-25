{hostVars, ...}: let
in {
  programs.vscode = {
    enable = true;

    profiles.default.userSettings = {
      "search.followSymlinks" = false;
      "search.useIgnoreFiles" = true;

      "files.watcherExclude" = {
        "**/.git/**" = true;
        "**/node_modules/**" = true;
        "**/dist/**" = true;
        "**/build/**" = true;
        "**/target/**" = true;
        "**/out/**" = true;
        "**/.direnv/**" = true;
        "**/.next/**" = true;
        "**/.turbo/**" = true;
        "**/result/**" = true;
      };

      "search.exclude" = {
        "**/.git" = true;
        "**/node_modules" = true;
        "**/dist" = true;
        "**/build" = true;
        "**/target" = true;
        "**/out" = true;
        "**/.direnv" = true;
        "**/.next" = true;
        "**/.turbo" = true;
        "**/result" = true;
      };

      "git.confirmSync" = false;
      "git.autofetch" = true;
      "git.enableSmartCommit" = true;
      "npm.autoDetect" = "off";
    };
  };
}
