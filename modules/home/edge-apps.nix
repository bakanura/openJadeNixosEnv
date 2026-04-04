{lib, pkgs, ...}: let
  edgeBin = "${pkgs.microsoft-edge}/bin/microsoft-edge";
  teamsProfileDir = ''"$HOME/.config/microsoft-edge-teams"'';
  edgeWrapper = pkgs.writeShellScript "nhl-edge" ''
    exec ${edgeBin} --password-store=basic "$@"
  '';
  teamsWrapper = pkgs.writeShellScript "nhl-microsoft-teams" ''
    mkdir -p "$HOME/.config/microsoft-edge-teams"
    exec ${edgeBin} \
      --password-store=basic \
      --class=teams-pwa \
      --name="Microsoft Teams" \
      --user-data-dir=${teamsProfileDir} \
      --app=https://teams.microsoft.com \
      "$@"
  '';
in {
  home.file.".local/bin/nhl-edge" = {
    executable = true;
    text = builtins.readFile edgeWrapper;
  };

  home.file.".local/bin/nhl-microsoft-teams" = {
    executable = true;
    text = builtins.readFile teamsWrapper;
  };

  home.file.".local/share/applications/microsoft-edge.desktop".text = ''
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft Edge
Exec=$HOME/.local/bin/nhl-edge %U
Terminal=false
Icon=microsoft-edge
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=microsoft-edge
  '';

  home.file.".local/share/applications/microsoft-teams.desktop".text = ''
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft Teams
Exec=$HOME/.local/bin/nhl-microsoft-teams
Terminal=false
Icon=microsoft-edge
Categories=Network;Office;InstantMessaging;
StartupNotify=true
StartupWMClass=teams-pwa
  '';

  home.activation.edgeAppRefresh = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
  '';
}
