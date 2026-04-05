{
  pkgs,
  host,
  username,
  ...
}: let
  repoRoot = "/home/${username}/NixOS-Hyprland";
  scriptsDir = "${repoRoot}/modules/tools/scripts";
  updateScript =
    builtins.replaceStrings
    ["__DEFAULT_HOST__" "__REPO_ROOT__"]
    [host repoRoot]
    (builtins.readFile ./scripts/update.sh);
  rebuildScript =
    builtins.replaceStrings
    ["__DEFAULT_HOST__" "__REPO_ROOT__"]
    [host repoRoot]
    (builtins.readFile ./scripts/rebuild.sh);
  lamabuddyScript = builtins.readFile ./scripts/lamabuddy.sh;
  helpScript =
    builtins.replaceStrings
    ["__SCRIPTS_DIR__"]
    [scriptsDir]
    (builtins.readFile ./scripts/help.sh);
in {
  environment.systemPackages = with pkgs; [
    # Command library entrypoint.
    (pkgs.writeShellScriptBin "helpme" helpScript)

    # Update and rebuild helpers.
    (pkgs.writeShellScriptBin "update" updateScript)
    (pkgs.writeShellScriptBin "rebuild" rebuildScript)
    (pkgs.writeShellScriptBin "lamabuddy" lamabuddyScript)
    (pkgs.writeShellScriptBin "cleanup" (builtins.readFile ./scripts/cleanup.sh))

    # Thermal troubleshooting helpers.
    (pkgs.writeShellScriptBin "thermal-status" (builtins.readFile ./scripts/thermal-status.sh))
    (pkgs.writeShellScriptBin "thermal-test" (builtins.readFile ./scripts/thermal-test.sh))
  ];
}
