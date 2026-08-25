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
    alejandra,
    ...
  }: let
    # =======================================================================
    # GLOBAL SYSTEM
    # =======================================================================

    system = "x86_64-linux";

    # =======================================================================
    # MACHINE-LOCAL HOST DISCOVERY
    #
    # Central configuration:
    #
    #   hosts/default/
    #
    # Machine-specific configuration:
    #
    #   .local-host/<hostname>/
    #
    # The installer creates the machine-local directory.
    #
    # We deliberately DO NOT use:
    #
    #   builtins.getEnv "NHL_HOSTNAME"
    #
    # because Nix flake evaluation must not depend on shell environment
    # variables.
    # =======================================================================

    localHostRoot = ./. + "/.local-host";

    localHostEntries =
      if builtins.pathExists localHostRoot
      then builtins.readDir localHostRoot
      else {};

    localHostNames =
      builtins.filter
        (
          name:
            localHostEntries.${name} == "directory"
            && name != "."
            && name != ".."
        )
        (builtins.attrNames localHostEntries);

    # =======================================================================
    # HOST IDENTITY
    #
    # Every machine-local host must contain:
    #
    #   .local-host/<hostname>/identity.json
    #
    # Example:
    #
    #   {
    #     "username": "baka"
    #   }
    # =======================================================================

    hostIdentity = host: let
      hostDir = ./. + "/.local-host/${host}";
      identityPath = hostDir + "/identity.json";

      identity =
        if builtins.pathExists identityPath
        then builtins.fromJSON (builtins.readFile identityPath)
        else {};
    in {
      username =
        if identity ? username
        && identity.username != null
        && identity.username != ""
        then identity.username
        else throw ''
          Host '${host}' is missing a username.

          Expected:

            .local-host/${host}/identity.json

          containing for example:

            {
              "username": "baka"
            }

          The installer must create identity.json before this host
          can be evaluated.
        '';
    };

    # =======================================================================
    # PACKAGES
    # =======================================================================

    pkgs = import nixpkgs {
      inherit system;

      config = {
        allowUnfree = true;
      };
    };

    pkgsUnstable = import nixpkgs-unstable {
      inherit system;

      config = {
        allowUnfree = true;
      };
    };

    waybarWeatherPkg =
      pkgs.callPackage ./pkgs/waybar-weather.nix {};

    clawCodeLocalPkg =
      pkgs.callPackage ./pkgs/claw-code-local.nix {};

  in {
    # =======================================================================
    # PACKAGES
    # =======================================================================

    packages.${system} = {
      waybar-weather = waybarWeatherPkg;
      claw-code-local = clawCodeLocalPkg;
    };

    # =======================================================================
    # NIXOS CONFIGURATIONS
    #
    # Every directory under:
    #
    #   .local-host/
    #
    # becomes:
    #
    #   nixosConfigurations.<hostname>
    #
    # Example:
    #
    #   .local-host/bakadesk-2657013e362a/
    #
    # becomes:
    #
    #   nixosConfigurations.bakadesk-2657013e362a
    #
    # hosts/default/ remains a template and is never directly instantiated.
    # =======================================================================

    nixosConfigurations =
      builtins.listToAttrs (
        map
          (
            host:
              let
                identity = hostIdentity host;
                username = identity.username;

                hostDir =
                  ./. + "/.local-host/${host}";
              in {
                name = host;

                value = nixpkgs.lib.nixosSystem {
                  inherit system;

                  specialArgs = {
                    inherit
                      inputs
                      username
                      host
                      pkgsUnstable;
                  };

                  modules = [
                    # -------------------------------------------------------
                    # MACHINE-LOCAL CONFIGURATION
                    # -------------------------------------------------------

                    (hostDir + "/config.nix")

                    # -------------------------------------------------------
                    # CENTRALLY MANAGED MODULES
                    # -------------------------------------------------------

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

                    # -------------------------------------------------------
                    # HOME MANAGER
                    # -------------------------------------------------------

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
                          host;
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
              }
          )
          localHostNames
      );

    # =======================================================================
    # FORMATTER
    # =======================================================================

    formatter.${system} =
      alejandra.defaultPackage.${system};
  };
}
