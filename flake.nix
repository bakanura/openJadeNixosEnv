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
  }: let
    # -----------------------------------------------------------------------
    # Global system
    # -----------------------------------------------------------------------
    system = "x86_64-linux";

    # -----------------------------------------------------------------------
    # Host discovery
    #
    # hosts/default/
    #
    #   This is the centrally managed template.
    #   It is intentionally NOT turned into a machine configuration.
    #
    # hosts/<hostname>/
    #
    #   These directories are generated locally by the installer.
    #   They do NOT need to be committed to Git.
    #
    # IMPORTANT:
    #
    # The installer must evaluate this flake through:
    #
    #   path:/absolute/path/to/repository
    #
    # rather than a normal Git flake reference.
    #
    # This allows Nix to see untracked machine-local host files.
    # -----------------------------------------------------------------------
    hostEntries = builtins.readDir ./hosts;

    hostNames =
      builtins.filter
        (
          name:
            name != "default"
            && hostEntries.${name} == "directory"
        )
        (builtins.attrNames hostEntries);

    # -----------------------------------------------------------------------
    # Host identity
    #
    # Every machine-local host must contain:
    #
    #   hosts/<hostname>/identity.json
    #
    # Example:
    #
    #   {
    #     "username": "baka"
    #   }
    # -----------------------------------------------------------------------
    hostIdentity = host: let
      identityPath = ./. + "/hosts/${host}/identity.json";

      identity =
        if builtins.pathExists identityPath
        then builtins.fromJSON (builtins.readFile identityPath)
        else {};
    in {
      username =
        if identity ? username && identity.username != null
        then identity.username
        else throw ''
          Host '${host}' is missing a username.

          Expected:

            hosts/${host}/identity.json

          containing for example:

            {
              "username": "baka"
            }

          The installer must create identity.json before this host
          can be evaluated.
        '';
    };

    # -----------------------------------------------------------------------
    # Packages
    # -----------------------------------------------------------------------
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
    # Packages
    # =======================================================================

    packages.${system} = {
      waybar-weather = waybarWeatherPkg;
      claw-code-local = clawCodeLocalPkg;
    };

    # =======================================================================
    # NixOS configurations
    #
    # Every directory under hosts/, except "default", becomes:
    #
    #   nixosConfigurations.<hostname>
    #
    # Example:
    #
    #   hosts/bakadesk-2657013e362a/
    #
    # becomes:
    #
    #   nixosConfigurations.bakadesk-2657013e362a
    #
    # No host needs to be manually added to this file.
    # =======================================================================

    nixosConfigurations =
      builtins.listToAttrs (
        map
          (
            host:
              let
                identity = hostIdentity host;
                username = identity.username;

                hostDir = ./. + "/hosts/${host}";
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
                    # Machine-local configuration
                    # -------------------------------------------------------
                    (hostDir + "/config.nix")

                    # -------------------------------------------------------
                    # Centrally managed modules
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
                    # Home Manager
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
          hostNames
      );

    # =======================================================================
    # Formatter
    # =======================================================================

    formatter.${system} =
      alejandra.defaultPackage.${system};
  };
}
