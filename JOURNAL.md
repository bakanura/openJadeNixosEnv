# Work Journal

This journal tracks the current round of requested fixes and follow-up work for the repo.

## Completed

- [x] Create a tracked journal for the current bugfix/addition batch.
- [ ] Improve USB dock detection, including dock-integrated LAN adapters.
- [ ] Keep the USB persistent block list across rebuilds.
- [x] Make `usb-guard --release` without a UUID open a reusable blocked-device picker.
- [ ] Remove duplicated rebuild chatter after sudo auth and fix the quiet-mode spinner line handling.
- [ ] Make fresh installs ask explicitly for hostname style instead of defaulting to `JODS-SERIAL`.
- [ ] Add extra fresh-install preflight checks for host template readiness.
- [ ] Improve Firefox/network reliability shortly after boot.
- [x] Move the stray repo-root `configuration.nix` into a proper aider/Ollama package module.
- [x] Fix Ollama GPU acceleration (500 runner crash): Resolved conflicts with claw-ollama module.
- [x] Add the `lamabuddy` wrapper command.
- [ ] Apply conservative performance tweaks without destabilizing the system.
- [ ] Fix Waybar power button behavior, tooltip text, and right-click menu behavior.
- [x] Fix GitHub API rate limits in update script using gh auth token.
- [x] Restore automatic USBGuard popups (fixed systemd env polling).
- [ ] Make power menu actions reliably reboot, power off, log out, and suspend/hibernate.
- [x] Fix GNOME Keyring auto-unlock on login via PAM.
- [ ] Fix Edge/Teams app launcher integration from the desktop launcher.
- [ ] Ensure the Teams desktop entry uses a Teams icon instead of the Edge icon.

## Notes

- Future install readiness should cover both the repo template and the interactive installer flow.
- Existing per-host profiles may still need selective follow-up if they intentionally diverged from `hosts/default`.
