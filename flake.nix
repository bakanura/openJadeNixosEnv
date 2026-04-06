{
  description = "KooL's NixOS-Hyprland";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim/main";
    #hyprland.url = "github:hyprwm/Hyprland"; # hyprland development
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
    system = "x86_64-linux";
    hostNames =
      builtins.filter
      (name: (builtins.readDir ./hosts)."${name}" == "directory")
      (builtins.attrNames (builtins.readDir ./hosts));
    hostIdentity = host: let
      identityPath = ./. + "/hosts/${host}/identity.json";
      identity =
        if builtins.pathExists identityPath
        then builtins.fromJSON (builtins.readFile identityPath)
        else {};
    in {
      username = identity.username or "roederp";
    };

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
    waybarWeatherPkg = pkgs.callPackage ./pkgs/waybar-weather.nix {};
    clawCodeLocalPkg = pkgs.callPackage ./pkgs/claw-code-local.nix {};
  in {
    packages.${system} = {
      waybar-weather = waybarWeatherPkg;
      claw-code-local = clawCodeLocalPkg;
    };
    nixosConfigurations = builtins.listToAttrs (
      map
      (
        host: let
          identity = hostIdentity host;
          username = identity.username;
        in {
          name = host;
          value = nixpkgs.lib.nixosSystem rec {
            specialArgs = {
              inherit system;
              inherit inputs;
              inherit username;
              inherit host;
              inherit pkgsUnstable;
            };
            modules = [
              (./. + "/hosts/${host}/config.nix")
              ./modules/overlays.nix
              ./modules/desktop
              ./modules/packages.nix
              ./modules/custom-ui
              ./modules/tools
              {nixpkgs.config.allowBroken = true;}
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
                home-manager.extraSpecialArgs = {inherit inputs system username host;};
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
    # Code formatter
    formatter.x86_64-linux = alejandra.defaultPackage.x86_64-linux;
  };
}
