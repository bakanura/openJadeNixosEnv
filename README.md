# NixOS-Hyprland (RISIQ)

A structured NixOS flake for deploying and maintaining a Hyprland-based workstation profile with:

- Host-specific configuration under `hosts/<hostname>/`
- Shared system modules under `modules/`
- Home Manager modules under `modules/home/`
- Installer workflows for initial setup and repeatable reconfiguration
- Security and session hardening defaults for production devices

This repository is designed for repeatable fleet-style setup while still allowing host-level customization.

Baseline inspiration:

- Frost Phoenix repository ([link](https://github.com/Frost-Phoenix/nixos-config)), adapted and expanded for this workflow by yours truly.
- JaKooLit Hyprland and NixOS work, especially the desktop UX and surrounding ecosystem:
  - [JaKooLit/NixOS-Hyprland](https://github.com/JaKooLit/NixOS-Hyprland)
  - [JaKooLit on GitHub](https://github.com/JaKooLit)

## Table of Contents

1. Scope
2. Repository layout
3. Prerequisites
4. Quick start
5. Installer workflows
6. Daily operations
7. Customization guide
8. Security and session behavior
9. Intune mode
10. VS Code management
11. Troubleshooting
12. Comment style guide

## Scope

Use this repository when you want:

- A reproducible NixOS desktop baseline on Hyprland
- Consistent install and rebuild flows
- Host-specific overrides without branching the whole codebase
- Managed first-login and fingerprint workflows

This repository does not include all Hyprland dotfiles directly. The installer can sync external Hyprland-Dots assets for user-facing desktop configuration.

## Repository layout

- `flake.nix`
  Defines inputs, outputs, selected host, and module wiring.

- `hosts/<host>/`
  Host profile files.
  - `config.nix`: Main host options (boot, services, networking, security)
  - `users.nix`: User account and shell config
  - `packages-fonts.nix`: Host-only packages and fonts
  - `variables.nix`: Host variables used by scripts and config
  - `hardware.nix`: Generated hardware config for the machine

- `modules/`
  Shared NixOS modules.
  - `desktop/`: Desktop shell, portals, theme, and login manager modules
  - `drivers/`: GPU profile modules collected behind one entrypoint
  - `hardware/`: Host hardware helpers such as VM guest services and local clock policy
  - `packages/`: Package composition split by category
  - `security/`: Fingerprint, session hardening, and USB guard modules
  - `power/`: Battery and power policy modules
  - `tools/`: Helper commands such as update/rebuild/cleanup plus `nh`
  - `custom-ui/`: Shared script-facing UI translation helpers
  - `entra/`: Managed deployment integration
  - Additional modules for drivers, theme, portals, login manager, overlays

- `modules/home/`
  Home Manager modules for CLI tools, editors, overview, first-login workflow, and VS Code.

- `scripts/lib/install-common.sh`
  Shared installer logic used by `install.sh` and `auto-install.sh`.

## Prerequisites

- NixOS installed (UEFI recommended)
- Git and required shell tools available
- Network access to flake inputs and package sources
- Sudo access during install and rebuild

## Quick start

### 1) Clone

```bash
git clone --depth 1 https://github.com/JaKooLit/NixOS-Hyprland.git ~/NixOS-Hyprland
cd ~/NixOS-Hyprland
```

### 2) Run installer

Automatic installer:

```bash
./auto-install.sh
```

In-repo installer (after clone):

```bash
./install.sh
```

### 3) Rebuild manually

```bash
sudo nixos-rebuild switch --flake .#<host>
```

## Installer workflows

### Auto enrollment behavior

The installer derives a hostname, detects whether the machine is already enrolled, and reuses an existing host profile when possible.

### Host profile generation

When no profile exists:

- Creates `hosts/<derived-host>/`
- Copies defaults from `hosts/default/`
- Generates `hardware.nix`

### Interactive selections

Installer can capture:

- Keyboard layout
- Timezone and console keymap
- Fingerprint enablement
- GPU profile toggles
- Optional firmware inspection/update

### Installer state persistence

Installer state is saved and reused for faster re-runs on the same host.

## Daily operations

### Validate and build

```bash
nix flake check
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
```

### Switch configuration

```bash
sudo nixos-rebuild switch --flake .#<host>
```

### Dry activate

```bash
sudo nixos-rebuild dry-activate --flake .#<host>
```

### Format Nix files

```bash
nix fmt
```

## Customization guide

### Add packages for all hosts

Edit module package composition in `modules/packages/`. Category packages live in their own modules under `modules/packages/system-packages/`, and higher-level package wiring lives under `modules/packages/environment/`, `modules/packages/programs/`, and `modules/packages/wine/`.

### Add packages for one host

Edit `hosts/<host>/packages-fonts.nix`.

### Change system behavior

Edit `hosts/<host>/config.nix` or add a targeted module in `modules/`.

### Add a new host

1. Copy default host template.
2. Set host name in `flake.nix` or via installer.
3. Generate host `hardware.nix`.
4. Rebuild with that host.

## Security and session behavior

Security modules are under:

- `modules/security/default.nix`
- `modules/security/fprintd-auth.nix`
- `modules/security/session-hardening.nix`
- `modules/security/usbguard/default.nix`

Current behavior includes:

- Fingerprint login support with password fallback
- Polkit rules for fingerprint enrollment by active local user
- Session hardening defaults for suspend and hibernate handling
- Hypridle respects D-Bus idle inhibitors when applications expose them
  - Browser meetings, video playback, screen sharing, and similar sessions can prevent idle dim/screen-off when the app correctly advertises an inhibit request
  - This depends on the application or browser actually sending the inhibit signal, so browser-based apps may be less reliable than native clients
- USBGuard review flow with dynamic built-in USB allowlisting
- Dock-aware USB review grouping for hubs, billboard helpers, Ethernet, and similar subdevices
- Separate high-warning review flow for storage-capable dock subdevices such as card readers or built-in driver partitions
- Lockscreen fail-safe watchdog:
  - Monitors lock process lifecycle
  - Terminates session if lock process dies while session remains locked
  - Forces re-login rather than leaving an unlocked active session

## Custom UI translation

Shared script-driven UI translation lives under:

- `modules/custom-ui/default.nix`
- `modules/custom-ui/translate.py`

Current behavior:

- English strings remain the source of truth in the repo
- Custom scripts can call the shared helper instead of implementing translation logic themselves
- DeepL translation is optional and falls back to English automatically
- Host-specific encrypted DeepL keys can live under `secrets/<host>/deepl-api-key.age`

Bootstrap helper:

```bash
custom-ui-translation-bootstrap-secret <host>
```

That helper reads `~/.config/deepl-api-key`, encrypts it for the current host using the host SSH key, and writes the result into the repo’s `secrets/` tree.

## Entra mode

Entra module path:

- `modules/entra/default.nix`
- `modules/entra/config.nix`

Enable per host:

```nix
local.entra.enable = true;
```

Optional settings:

```nix
local.entra.nonInteractive = true;
local.entra.deviceId = "optional-device-id";
local.entra.installPortal = true;
local.entra.installEdge = true;
```

When enabled:

- Exposes `ENTRA_MANAGED=1` and `ENTRA_NONINTERACTIVE`
- Exposes optional `ENTRA_DEVICE_ID`
- Exposes `INTUNE_MANAGED=1` and `NHL_NONINTERACTIVE` for installer logic
- Exposes optional `INTUNE_DEVICE_ID`
- Adds `/etc/risiq/entra-managed` marker
- Writes `/etc/risiq/entra/managed.conf` configuration
- Installs `intune-portal` (Microsoft Intune Portal client)
- Installs `microsoft-edge` (recommended for Conditional Access)
- Installs helper commands: `entra-status`, `intune-status`, `entra-enroll`, `intune-enroll`
- Starts user service `entra-intune-daemon` during graphical session

## VS Code management

VS Code module path:

- `modules/home/vscode/`
  - `package.nix`
  - `extensions.nix`
  - `settings.nix`

Extension sync behavior:

- Installs declared extensions
- Uses a state marker to avoid repeating full sync on every activation
- Runs in background to avoid blocking rebuild completion

## Troubleshooting

### Flake cannot find new module file

If a new module file exists locally but flake evaluation says it does not exist, stage it:

```bash
git add <new-file>
```

Flake evaluation uses the Git tree snapshot.

### Rebuild unit conflict

If `nixos-rebuild-switch-to-configuration.service` is already loaded:

```bash
sudo systemctl stop nixos-rebuild-switch-to-configuration.service
sudo systemctl reset-failed nixos-rebuild-switch-to-configuration.service
sudo systemctl daemon-reload
```

### Network fetch timeouts

If sources fail to resolve:

- Verify DNS and network connectivity
- Retry rebuild/update
- Use cached inputs when available

### Home Manager appears stuck

Check Home Manager logs:

```bash
journalctl -u home-manager-<user>.service -n 200 --no-pager
```

## Comment style guide

This repository uses the following comment rules:

- Use sentence case.
- Keep comments concise and technical.
- Use one-line comments where possible.
- Use imperative style for actionable notes.
- Avoid decorative comments, emojis, slang, and conversational phrasing.
- Avoid redundant comments that restate obvious code.

Examples:

- Good: `# Configure networking.`
- Good: `# Update the host field in flake.nix (first occurrence).`
- Avoid: decorative banners, jokes, and all-caps non-technical notes.
