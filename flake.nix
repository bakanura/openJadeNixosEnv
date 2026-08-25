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

  outputs =
    inputs @ {
      self,
      nixpkgs,
      nixpkgs-unstable,
      alejandra,
      ...
    }:
    let
      system = "x86_64-linux";

      # ---------------------------------------------------------------------
      # Machine-local host directory
      #
      # The installer sets NHL_HOST_DIR to something like:
      #
      #   /home/baka/.config/openjade-nixos/hosts/bakadesk-2657013e362a
      #
      # This directory is deliberately OUTSIDE the Git repository.
      #
      # The flake therefore does not need to discover or track machine
      # configurations in Git.
      # ---------------------------------------------------------------------
      hostDirString = builtins.getEnv "NHL_HOST_DIR";

      hostDir =
        if hostDirString != "" then
          /. + hostDirString
        else
          throw ''
            NHL_HOST_DIR is not set.

            This flake requires the installer to provide the machine-local
            host directory through the NHL_HOST_DIR environment variable.

            Example:

              export NHL_HOST_DIR=/home/user/.config/openjade-nixos/hosts/myhost

            Then evaluate the flake with:

              nix --impure ...
          '';

      # ---------------------------------------------------------------------
      # Validate the host directory.
      # ---------------------------------------------------------------------
      hostDirExists =
        builtins.pathExists hostDir;

      hostConfigPath =
        hostDir + "/config.nix";

      hostIdentityPath =
        hostDir + "/identity.json";

      hostConfigExists =
        builtins.pathExists hostConfigPath;

      hostIdentityExists =
        builtins.pathExists hostIdentityPath;

      # ---------------------------------------------------------------------
      # Host identity
      # ---------------------------------------------------------------------
      hostIdentity =
        if hostIdentityExists then
          builtins.fromJSON (
            builtins.readFile hostIdentityPath
          )
        else
          throw ''
            Machine-local host identity is missing:

              ${hostIdentityPath}

            The installer must create identity.json before evaluating
            the NixOS configuration.
          '';

      username =
        if hostIdentity ? username then
          hostIdentity.username
        else
          throw ''
            Host identity is missing the required "username" field:

              ${hostIdentityPath}

            Expected format:

              {
                "username": "baka"
              }
          '';

      # ---------------------------------------------------------------------
      # Host name
      #
      # NHL_HOST_NAME is supplied by the installer.
      # ---------------------------------------------------------------------
      hostName =
        let
          value = builtins.getEnv "NHL_HOST_NAME";
        in
          if value != "" then
            value
          else
            throw ''
              NHL_HOST_NAME is not set.

              The installer must provide the hostname when evaluating
              this machine-local configuration.
            '';

      # ---------------------------------------------------------------------
      # Packages
      # ---------------------------------------------------------------------
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
        pkgs.callPackage ./pkgs/waybar-weather.nix { };

      clawCodeLocalPkg =
        pkgs.callPackage ./pkgs/claw-code-local.nix { };

    in
    {
      # ---------------------------------------------------------------------
      # Packages
      # ---------------------------------------------------------------------
      packages.${system} = {
        waybar-weather = waybarWeatherPkg;
        claw-code-local = clawCodeLocalPkg;
      };

      # ---------------------------------------------------------------------
      # Machine-local NixOS configuration
      # ---------------------------------------------------------------------
      nixosConfigurations.${hostName} =
        nixpkgs.lib.nixosSystem rec {
          specialArgs = {
            inherit
              system
              inputs
              username
              hostName
              pkgsUnstable;

            # Existing config.nix expects "host".
            host = hostName;
          };

          modules = [
            hostConfigPath

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
                  hostName;

                host = hostName;
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

      # ---------------------------------------------------------------------
      # Code formatter
      # ---------------------------------------------------------------------
      formatter.${system} =
        alejandra.defaultPackage.${system};
    };
}
