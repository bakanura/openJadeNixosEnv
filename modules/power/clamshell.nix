{ config, pkgs, ... }:

{
  # Configure logind to allow clamshell mode.
  # This prevents the laptop from suspending/hibernating when the lid is closed 
  # IF an external monitor is connected (Docked) or if it's plugged into power.
  services.logind = {
    lidSwitch = "hibernate";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
  };
}