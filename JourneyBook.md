# JourneyBook

This document is the repo's guided handbook for both people and AI assistants working in `NixOS-Hyprland`.

It is mainly meant for people who want to adapt the repo to their own needs but do not always have the time or deep repository knowledge required to untangle everything quickly. In those cases, this file gives both humans and AI agents a shared map of the repo so they can work through changes confidently instead of guessing across a fast-growing codebase.

## Common commands

- Rebuild and switch the system (uses the host configured in the selected host directory):
  - `sudo nixos-rebuild switch --flake .#<host>`
  - Dry-run validation without switching: `sudo nixos-rebuild dry-activate --flake .#<host>`
  - Build only: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
- Format Nix code:
  - `nix fmt`
- Update inputs:
  - `nix flake update`
- Evaluate the flake:
  - `nix flake check`

## Big-picture architecture

This repo is a NixOS flake that assembles a Hyprland-based desktop and a small Home Manager profile. It intentionally does not ship Hyprland dotfiles; those are pulled by the installer from a separate repository.

- Flake wiring (`flake.nix`)
  - Inputs: `nixpkgs` (25.11), `home-manager` (25.11), `nixvim`, `alejandra`, `catppuccin`, and `quickshell`.
  - Outputs: `nixosConfigurations.<host>` for each host directory under `hosts/`.
  - Per-host identity is resolved from `hosts/<host>/identity.json`.

- Host layouts (`hosts/<name>/`)
  - `config.nix` is the main machine profile.
  - `users.nix` defines the primary user and shell-related settings.
  - `packages-fonts.nix` contains host-specific packages/fonts.
  - `variables.nix` centralizes smaller tunables.
  - `hardware.nix` is generated per machine during install.
  - `identity.json` stores the host's selected username for flake/Home Manager wiring.

- System modules (`modules/`)
  - `modules/desktop/` for the desktop/session layer.
  - `modules/drivers/` for GPU profiles.
  - `modules/hardware/` for hardware helpers.
  - `modules/packages/` for system-wide package composition.
  - `modules/tools/` for custom helpers (update, cleanup, thermal tools, and `clawbuddy` AI wrappers).
  - `modules/security/` for fingerprint/session/USB policies.
  - `modules/power/`, `modules/custom-ui/`, `modules/entra/`, and `modules/home/` for the remaining focused areas.

## Typical development flows

- Change software for every machine: edit `modules/packages/`, then rebuild.
- Change software for one machine: edit `hosts/<name>/packages-fonts.nix`, then rebuild.
- Change services or hardware behavior: edit `hosts/<name>/config.nix` or a focused module under `modules/`, then rebuild.
- Create a new host:
  1. Copy `hosts/default` to `hosts/<newname>`.
  2. Let the installer populate `identity.json` and `hardware.nix`.
  3. Rebuild with `--flake .#<newname>`.

## Tests and linting

- There is no dedicated unit/integration test suite.
- Use `nixos-rebuild dry-activate` and `nix flake check` for validation.
- Nix formatting is handled via `nix fmt`.

## Troubleshooting Ollama (clawbuddy/lamabuddy)

If you see `llama runner process has terminated` (500 error):
1. Check if the correct GPU driver is enabled in `hosts/<host>/config.nix`.
2. Verify the Ollama service is using that driver: `systemctl status ollama.service`.
3. Ensure your user (e.g., `roederp`) is in the `video` and `render` groups in `users.nix`.
4. On AMD GPUs, you **must** set `services.ollama.rocmOverrideGfx = "10.3.0";` in your host config to prevent the runner from crashing.
5. Run `journalctl -u ollama.service -f` while launching `clawbuddy` to see specific library load errors.
