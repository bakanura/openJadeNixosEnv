{
  config,
  lib,
  ...
}: let
  overviewSource = ./overview;
in {
  # Quickshell-overview is a Qt6 QML app for Hyprland workspace overview
  # Toggled via: SUPER + TAB (added to Hyprland config separately)
  # Started via: exec-once = qs -c overview (added to Hyprland config separately)

  # Seed the Quickshell overview code into ~/.config/quickshell/overview
  # Copy (not symlink) so QML module resolution works and users can edit files
  home.activation.seedOverviewCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    DEST="$HOME/.config/quickshell/overview"
    SRC="${overviewSource}"
    ROOT_SHELL="$HOME/.config/quickshell/shell.qml"

    mkdir -p "$HOME/.config/quickshell"
    # Remove old directory and copy fresh (ensures QML updates are picked up)
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    chmod -R u+rwX "$DEST"

    # Keep a default entry point so plain `qs` still works right after a rebuild.
    cat > "$ROOT_SHELL" <<'EOF'
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "./overview/modules/overview/"
import "./overview/services/"
import "./overview/common/"
import "./overview/common/functions/"
import "./overview/common/widgets/"

import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    Overview {}
}
EOF
  '';
}
