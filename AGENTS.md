# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common commands

- Rebuild and switch the system (uses the host configured in `flake.nix`):
  - sudo nixos-rebuild switch --flake .#<host>
  - Dry-run validation without switching: sudo nixos-rebuild dry-activate --flake .#<host>
  - Build only (checks evaluation and produces a toplevel derivation): nix build .#nixosConfigurations.<host>.config.system.build.toplevel
- Format Nix code (flake formatter is Alejandra):
  - nix fmt
- Update inputs (refreshes `flake.lock`):
  - nix flake update
- Evaluate the flake (lightweight sanity check):
  - nix flake check

Notes
- This flake exposes a single `nixosConfigurations` entry named after the `host` value in `flake.nix`. If you create a new host (see below), update `host = "..."` in `flake.nix` or use the provided installer to do it for you before rebuilding.
- On systems built from this flake, `programs.nh` is enabled with the flake path set to `~/NixOS-Hyprland`. If installed, `nh` can be used to rebuild from that path (optional convenience outside CI).

## Big-picture architecture

This repo is a NixOS flake that assembles a Hyprland-based desktop and a small Home Manager profile. It intentionally does not ship Hyprland dotfiles; those are pulled by the installer from a separate repository.

- Flake wiring (`flake.nix`)
  - Inputs: `nixpkgs` (25.11), `home-manager` (25.11), `nixvim`, `alejandra` (formatter), `catppuccin`, and `quickshell`.
  - One output: `nixosConfigurations."${host}"`, where `host` is a string set in `flake.nix`. That configuration imports `./hosts/${host}/config.nix` and several local modules under `modules/` (see below), and integrates Home Manager as a NixOS module.
  - Formatter: `formatter.x86_64-linux = alejandra` so `nix fmt` uses Alejandra.

- Host layouts (`hosts/<name>/`)
  - `config.nix` is the main machine profile (kernel, services, bootloader, Bluetooth, audio, OpenGL, Polkit, etc.). It references toggles like `drivers.*`, `vm.guest-services.enable`, and imports per-host files.
  - `users.nix` defines the primary user, shell, and shell plugins.
  - `packages-fonts.nix` holds extra system packages for that host. It also demonstrates how Python packages for scripts are added.
  - `variables.nix` centralizes small tunables (e.g., keyboard layout, default apps). Install scripts and prompts update these values.
  - `hardware.nix` is generated per machine via `nixos-generate-config` (installer handles this).

- System modules (`modules/`)
  - Desktop/runtime modules live under `modules/desktop/` (`quickshell.nix`, `portals.nix`, `theme.nix`, `ly.nix`) and are imported via `modules/desktop/default.nix`.
  - GPU profiles live under `modules/drivers/` and are imported via `modules/drivers/default.nix`; hosts toggle them with the existing `drivers.*` options.
  - Hardware helpers such as VM guest services and local hardware clock policy live under `modules/hardware/`.
  - Package composition lives under `modules/packages/`, with summary imports in `modules/packages/default.nix` and leaf package categories in `modules/packages/system-packages/`.
  - Custom script UI translation lives under `modules/custom-ui/`.
  - Helper commands and `nh` live under `modules/tools/`.
  - `modules/entra/` holds the managed Entra/Intune integration.
  - `overlays.nix` provides targeted package fixes (e.g., CMake policy minimums, a `cxxopts` pkg-config shim, ANTLR CPP tweaks, `pamixer` build env). This keeps the flake stable on newer CMake/toolchains without forking packages.

- Home Manager (`modules/home/`)
  - A minimal profile focused on CLI/terminal tooling (tmux, Ghostty, nixvim, bat, bottom/btop, eza, fzf, git, htop, tealdeer) plus a QuickShell-based overview under `modules/home/overview/` (QML and assets). These are imported via `modules/home/default.nix` and attached to the primary user in `flake.nix`.

- Installers (`auto-install.sh`, `install.sh`, `scripts/lib/install-common.sh`)
  - These scripts are for first-time setup on NixOS. They:
    - Clone the repo into `~/NixOS-Hyprland`.
    - Create a new host by copying `hosts/default` if you provide a hostname.
    - Detect GPU/VM and toggle the appropriate module switches in the host config (`nhl_detect_gpu_and_toggle`).
    - Prompt for keyboard layout and timezone/console keymap, then patch host files.
    - Generate `hardware.nix` and run `sudo nixos-rebuild switch --flake ~/NixOS-Hyprland/#<host>`.
    - Optionally fetch themes/icons and the separate Hyprland dotfiles repository.

## Typical development flows

- Add or change packages for all machines: edit `modules/packages/` (usually `modules/packages/system-packages/` or one of the package summary modules), then rebuild.
- Add or change packages for one machine: edit `hosts/<name>/packages-fonts.nix`, then rebuild.
- Tweak services/system options: edit `hosts/<name>/config.nix` (or a focused module under `modules/`), then rebuild.
- Create a new host:
  1) Copy `hosts/default` to `hosts/<newname>` and edit as needed.
  2) Update `host = "<newname>";` in `flake.nix` (the installers can automate this),
  3) Generate `hardware.nix` for that host, and rebuild with `--flake .#<newname>`.

## Tests and linting

- There is no explicit unit/integration test suite in this repo. Use `nixos-rebuild dry-activate` and `nix flake check` for evaluation sanity.
- Nix formatting is enforced via `nix fmt` (Alejandra). No additional lint tools are wired in the flake.
