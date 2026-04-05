{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bandwhich
    caligula
    cpufetch
    cpuid
    cpu-x
    cyme
    gdu
    glances
    gping
    htop
    hyfetch
    ipfetch
    pfetch
    smartmontools
    lm_sensors
    mission-center
  ];
}
