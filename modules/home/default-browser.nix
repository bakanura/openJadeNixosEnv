{
  host,
  lib,
  osConfig ? null,
  ...
}: let
  hostVars = import ../../hosts/${host}/variables.nix;
  configuredBrowser = hostVars.browser or "firefox";
  browserDesktop =
    if configuredBrowser == "google-chrome-stable"
    then "google-chrome.desktop"
    else if configuredBrowser == "microsoft-edge"
    then "microsoft-edge.desktop"
    else "firefox.desktop";
in {
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/xhtml+xml" = [browserDesktop];
      "text/html" = [browserDesktop];
      "x-scheme-handler/about" = [browserDesktop];
      "x-scheme-handler/http" = [browserDesktop];
      "x-scheme-handler/https" = [browserDesktop];
      "x-scheme-handler/unknown" = [browserDesktop];
    };
  };

  home.activation.forceDefaultBrowser = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v xdg-settings >/dev/null 2>&1; then
      xdg-settings set default-web-browser ${browserDesktop} >/dev/null 2>&1 || true
    fi
  '';
}
