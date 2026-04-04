{...}: {
  imports = [
    ./fprintd-auth.nix
    ./session-hardening.nix
    ./usbguard
  ];
}
