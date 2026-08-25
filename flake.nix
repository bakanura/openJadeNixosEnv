{
  description = "KooL's NixOS-Hyprland";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim/main";

    alejandra.url = "github:kamadorueda/alejandra";

    ags = {
      type = "github";
      owner = "aylur";
      repo = "ags";
      ref = "v1";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      # Official mirror per quickshell docs; avoids outfoxxed.me DNS outages.
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    ags,
    alejandra,
    ...
  }:
    let
      # =====================================================================
      # GLOBAL SYSTEM
      # =====================================================================

      system = "x86_64-linux";

      # =====================================================================
      # MACHINE-LOCAL HOST ROOT
      #
      # The Git repository contains only the centrally managed template:
      #
      #   hosts/default/
      #
      # Machine-specific files live outside the Git-tracked flake source:
      #
      #   .local-host/<hostname>/
      #
      # The installer exports:
      #
      #   NHL_LOCAL_HOST_ROOT=/absolute/path/to/repo/.local-host
      #
      # and invokes Nix with --impure.
      #
      # This is intentional. Git-backed flakes only expose tracked files to
      # the flake evaluation store, so machine-local configuration cannot be
      # discovered with builtins.readDir ./.
      # =====================================================================

      localHostRoot =
        let
          root = builtins.getEnv "NHL_LOCAL_HOST_ROOT";
        in
          if root != ""
          then root
          else
            throw ''
              NHL_LOCAL_HOST_ROOT is not set.

              This installation uses machine-local host configuration.

              Expected environment variable:

                NHL_LOCAL_HOST_ROOT=/absolute/path/to/.local-host

              Example:

                export NHL_LOCAL_HOST_ROOT="$PWD/.local-host"

              Then evaluate the flake with:

                nix --impure flake show

              or:

                nixos-rebuild switch --impure --flake .#<hostname>
            '';

      # =====================================================================
      # MACHINE-LOCAL HOSTNAME
      #
      # The installer exports:
      #
      #   NHL_HOSTNAME=<hostname>
      #
      # We deliberately require it instead of automatically discovering every
      # directory under .local-host/.
      #
      # This prevents one machine from accidentally exposing another machine's
      # configuration as a NixOS configuration.
      # =====================================================================

      localHostName =
        let
          hostname = builtins.getEnv "NHL_HOSTNAME";
        in
          if hostname != ""
          then hostname
          else
            throw ''
              NHL_HOSTNAME is not set.

              The installer must select a hostname before evaluating the
              machine-local NixOS configuration.

              Example:

                export NHL_HOSTNAME=bakadesk-2657013e362a
            '';

      # =====================================================================
      # MACHINE-LOCAL HOST DIRECTORY
      # =====================================================================

      hostDir =
        builtins.toPath "${localHostRoot}/${localHostName}";

      # =====================================================================
      # MACHINE-LOCAL IDENTITY
      #
      # Expected:
      #
      #   .local-host/<hostname>/identity.json
      #
      # Example:
      #
      #   {
      #     "username": "baka"
      #   }
      # =====================================================================

      identityPath =
        hostDir + "/identity.json";

      hostIdentity =
        if builtins.pathExists identityPath
        then
          builtins.fromJSON (
            builtins.readFile identityPath
          )
        else
          throw ''
            Machine-local host identity is missing.

            Expected:

              ${toString identityPath}

            The installer must create identity.json before evaluating
            this NixOS configuration.

            Expected contents:

              {
                "username": "baka"
              }
          '';

      username =
        if hostIdentity ? username
          && hostIdentity.username != null
          && hostIdentity.username != ""
        then
          hostIdentity.username
        else
          throw ''
            Machine-local host identity does not contain a valid username.

            File:

              ${toString identityPath}

            Expected:

              {
                "username": "baka"
              }
          '';

      # =====================================================================
      # PACKAGES
      # =====================================================================

      pkgs =
        import nixpkgs {
          inherit system;

          config = {
            allowUnfree = true;
          };
        };

      pkgsUnstable =
        import nixpkgs-unstable {
          inherit system;

          config = {
            allowUnfree = true;
          };
        };

      waybarWeatherPkg =
        pkgs.callPackage ./pkgs/waybar-weather.nix {};

      clawCodeLocalPkg =
        pkgs.callPackage ./pkgs/claw-code-local.nix {};

    in
    {
      # =====================================================================
      # PACKAGES
      # =====================================================================

      packages.${system} = {
        waybar-weather = waybarWeatherPkg;
        claw-code-local = clawCodeLocalPkg;
      };

      # =====================================================================
      # NIXOS CONFIGURATION
      #
      # The machine-local config is the copy generated by the installer:
      #
      #   .local-host/<hostname>/config.nix
      #
      # That config imports its local siblings:
      #
      #   ./hardware.nix
      #   ./users.nix
      #   ./packages-fonts.nix
      #   ./variables.nix
      #
      # Therefore the entire machine profile remains self-contained inside
      # .local-host/<hostname>/.
      # =====================================================================

      nixosConfigurations = {
        "${localHostName}" =
          nixpkgs.lib.nixosSystem {
            inherit system;

            # ---------------------------------------------------------------
            # Arguments available to all modules
            # ---------------------------------------------------------------

            specialArgs = {
              inherit
                inputs
                system
                username
                pkgsUnstable
                localHostName
                hostDir;

              # Preserve the existing "host" argument expected by modules.
              host = localHostName;
            };

            # ---------------------------------------------------------------
            # Modules
            # ---------------------------------------------------------------

            modules = [
              # =============================================================
              # MACHINE-LOCAL CONFIGURATION
              # =============================================================

              "${toString hostDir}/config.nix"

              # =============================================================
              # CENTRALLY MANAGED MODULES
              # =============================================================

              ./modules/overlays.nix
              ./modules/desktop
              ./modules/packages.nix
              ./modules/custom-ui
              ./modules/tools

              {
                nixpkgs.config.allowBroken = true;
              }

              ./modules/fonts.nix
              ./modules/security/default.nix
              ./modules/entra
              ./modules/power.nix

              # =============================================================
              # HOME MANAGER
              # =============================================================

              inputs.home-manager.nixosModules.home-manager

              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.backupFileExtension = "hm-bak";
                home-manager.overwriteBackup = true;

                home-manager.extraSpecialArgs = {
                  inherit
                    inputs
                    system
                    username
                    hostDir;

                  host = localHostName;
                };

                home-manager.users.${username} = {
                  home.username = username;
                  home.homeDirectory = "/home/${username}";
                  home.stateVersion = "24.05";

                  imports = [
                    ./modules/home/default.nix
                  ];
                };
              }
            ];
          };
      };

      # =====================================================================
      # FORMATTER
      # =====================================================================

      formatter.${system} =
        alejandra.defaultPackage.${system};
    };
}
