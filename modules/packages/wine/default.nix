{
  pkgs,
  username,
  ...
}: let
  defaultPrefix = "/home/${username}/.local/share/wineprefixes/default";
in {
  environment.sessionVariables = {
    WINEPREFIX = defaultPrefix;
    WINEARCH = "win64";
    WINEESYNC = "1";
    WINEFSYNC = "1";
    WINEDLLOVERRIDES = "winemenubuilder.exe=d";
    DXVK_LOG_LEVEL = "none";
  };

  systemd.tmpfiles.rules = [
    "d ${defaultPrefix} 0700 ${username} users - -"
    "d /home/${username}/.local/share/wineprefixes 0700 ${username} users - -"
  ];

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "wineprefix-init" ''
      set -euo pipefail
      prefix="''${WINEPREFIX:-${defaultPrefix}}"
      marker="$prefix/.nhl-runtime-seeded-v1"
      export NHL_WINEPREFIX_INIT_RUNNING=1

      mkdir -p "$prefix"
      wineboot -u

      if [ ! -e "$marker" ]; then
        wine_root="$(dirname "$(dirname "$(command -v wine)")")"
        mono_msi="$(find "$wine_root/share/wine/mono" -maxdepth 1 -name 'wine-mono-*.msi' 2>/dev/null | head -n 1 || true)"
        gecko_msi="$(find "$wine_root/share/wine/gecko" -maxdepth 1 -name 'wine-gecko-*.msi' 2>/dev/null | head -n 1 || true)"

        if [ -n "$mono_msi" ]; then
          wine msiexec /i "$mono_msi" /qn /norestart >/dev/null 2>&1 || true
        fi

        if [ -n "$gecko_msi" ]; then
          wine msiexec /i "$gecko_msi" /qn /norestart >/dev/null 2>&1 || true
        fi

        touch "$marker"
      fi
    '')
    (pkgs.writeShellScriptBin "wineprefix-path" ''
      printf '%s\n' "${defaultPrefix}"
    '')
  ];
}
