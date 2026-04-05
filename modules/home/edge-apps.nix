{
  config,
  lib,
  pkgs,
  ...
}: let
  edgeBin = "${pkgs.microsoft-edge}/bin/microsoft-edge";
  localBinDir = "${config.home.homeDirectory}/.local/bin";
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
  teamsIcon = ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
      <rect x="28" y="24" width="68" height="80" rx="16" fill="#4f52d0"/>
      <circle cx="96" cy="48" r="16" fill="#7b83eb"/>
      <circle cx="104" cy="78" r="14" fill="#6366da"/>
      <rect x="12" y="34" width="44" height="60" rx="10" fill="#6366da"/>
      <path d="M28 48h28v10H47v30H37V58H28z" fill="#fff"/>
    </svg>
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

  home.file.".local/share/icons/hicolor/scalable/apps/microsoft-teams.svg".text = teamsIcon;

  home.file.".local/share/applications/microsoft-edge.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Microsoft Edge
    Exec=${localBinDir}/nhl-edge %U
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
    Exec=${localBinDir}/nhl-microsoft-teams
    Terminal=false
    Icon=microsoft-teams
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
