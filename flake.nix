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

  outputs =
    inputs @ { self
    , nixpkgs
    , nixpkgs-unstable
    , ags
    , alejandra
    , ...
    }:
    let
      system = "x86_64-linux";
      host = "RISIQ-4ecb329e0225";
      username = "roederp";

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
      waybarWeatherPkg = pkgs.callPackage ./pkgs/waybar-weather.nix { };
    in
    {
      packages.${system} = {
        waybar-weather = waybarWeatherPkg;
      };
      nixosConfigurations = {
        "${host}" = nixpkgs.lib.nixosSystem rec {
          specialArgs = {
            inherit system;
            inherit inputs;
            inherit username;
            inherit host;
            inherit pkgsUnstable;
          };
          modules = [
            ./hosts/${host}/config.nix
            # inputs.distro-grub-themes.nixosModules.${system}.default
            ./modules/overlays.nix # nixpkgs overlays (CMake policy fixes)
            ./modules/desktop # desktop shell, portals, theme, login manager
            ./modules/packages.nix # Software packages
            ./modules/custom-ui # shared translation helper for custom UI scripts
            ./modules/tools # helper commands and nh integration
            # Allow broken packages (temporary fix for broken CUDA in nixos-unstable)
            { nixpkgs.config.allowBroken = true; }
            ./modules/fonts.nix # Fonts packages
            ./modules/security/default.nix # fingerprint auth + session hardening
            ./modules/entra # optional Entra/Intune managed deployment mode
            ./modules/power.nix # battery charge thresholds (95% default)
            # Temporarily disabled: current catppuccin module in lockfile references
            # services.displayManager.generic, which is invalid on this NixOS release.
            # inputs.catppuccin.nixosModules.catppuccin
            # Integrate Home Manager as a NixOS module
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-bak";

              # Ensure HM modules can access flake inputs (e.g., inputs.nixvim)
              home-manager.extraSpecialArgs = { inherit inputs system username host; };

              home-manager.users.${username} = {
                home.username = username;
                home.homeDirectory = "/home/${username}";
                home.stateVersion = "24.05";

                # Import your copied HM modules
                imports = [
                  ./modules/home/default.nix
                ];
              };
            }
          ];
        };
      };
      # Code formatter
      formatter.x86_64-linux = alejandra.defaultPackage.x86_64-linux;
    };
}
