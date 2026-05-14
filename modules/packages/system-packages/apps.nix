{
  pkgs,
  config,
  pkgsUnstable ? null,
  ...
}: let
  cudaEnabled = config.drivers.nvidia.enable || config.drivers.nvidia-prime.enable;
  wineSource =
    if pkgsUnstable != null
    then pkgsUnstable
    else pkgs;
  winePkgBase =
    if builtins.hasAttr "wineWow64Packages" wineSource && builtins.hasAttr "stagingFull" wineSource.wineWow64Packages
    then wineSource.wineWow64Packages.stagingFull
    else pkgs.wineWow64Packages.stagingFull;
  winePkg = winePkgBase.override {
    embedInstallers = true;
  };
  nvtopPackage =
    if cudaEnabled
    then pkgs.nvtopPackages.full
    else if builtins.hasAttr "amd" pkgs.nvtopPackages
    then pkgs.nvtopPackages.amd
    else if builtins.hasAttr "intel" pkgs.nvtopPackages
    then pkgs.nvtopPackages.intel
    else pkgs.nvtopPackages.full;
  wineRun = pkgs.writeShellScriptBin "wine-run" ''
    set -euo pipefail

    export WINEESYNC="''${WINEESYNC:-1}"
    export WINEFSYNC="''${WINEFSYNC:-1}"
    export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    export DXVK_LOG_LEVEL="''${DXVK_LOG_LEVEL:-none}"

    if [ "''${NHL_WINEPREFIX_INIT_RUNNING:-0}" != "1" ] && command -v wineprefix-init >/dev/null 2>&1; then
      wineprefix-init
    fi

    if command -v gamemoderun >/dev/null 2>&1; then
      exec gamemoderun ${winePkg}/bin/wine "$@"
    fi

    exec ${winePkg}/bin/wine "$@"
  '';
  wineCompatLaunchers = pkgs.writeShellScriptBin "wine" ''
    set -euo pipefail
    exec ${wineRun}/bin/wine-run "$@"
  '';
  wine64Compat = pkgs.writeShellScriptBin "wine64" ''
    set -euo pipefail

    export WINEESYNC="''${WINEESYNC:-1}"
    export WINEFSYNC="''${WINEFSYNC:-1}"
    export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    export DXVK_LOG_LEVEL="''${DXVK_LOG_LEVEL:-none}"

    if [ "''${NHL_WINEPREFIX_INIT_RUNNING:-0}" != "1" ] && command -v wineprefix-init >/dev/null 2>&1; then
      wineprefix-init
    fi

    if command -v gamemoderun >/dev/null 2>&1; then
      exec gamemoderun ${winePkg}/bin/wine64 "$@"
    fi

    exec ${winePkg}/bin/wine64 "$@"
  '';
in {
  environment.systemPackages = with pkgs; [
    android-tools
    loupe
    appimage-run
    bc
    brightnessctl
    (btop.override {
      cudaSupport = cudaEnabled;
      rocmSupport = true;
    })
    bottom
    baobab
    btrfs-progs
    cmatrix
    distrobox
    dua
    duf
    cava
    cargo
    clang
    cmake
    cliphist
    cpufrequtils
    curl
    dysk
    eog
    eza
    findutils
    figlet
    ffmpeg
    fd
    feh
    file-roller
    bottles
    glib
    gsettings-qt
    git
    nextcloud-client
    firefox
    gnome-system-monitor
    fastfetch
    jq
    gcc
    python3
    gnumake
    grim
    grimblast
    gtk-engine-murrine
    inxi
    imagemagick
    killall
    kdePackages.qt6ct
    kdePackages.qtwayland
    kdePackages.qtstyleplugin-kvantum
    lazydocker
    lazygit
    libappindicator
    libnotify
    libsForQt5.qtstyleplugin-kvantum
    libsForQt5.qt5ct
    (mpv.override {scripts = [mpvScripts.mpris];})
    nvtopPackage
    openssl
    pciutils
    usbutils
    networkmanagerapplet
    pamixer
    pavucontrol
    playerctl
    kdePackages.polkit-kde-agent-1
    rofi
    slurp
    swappy
    serie
    swaynotificationcenter
    swww
    unzip
    vkd3d
    wallust
    wdisplays
    wl-clipboard
    wlr-randr
    xrandr
    wlogout
    wget
    wineCompatLaunchers
    wine64Compat
    wineRun
    winePkg
    winetricks
    protontricks
    mono
    xarchiver
    yad
    yazi
    xdg-user-dirs
    yt-dlp
    dxvk
    gamemode
    keepassxc
    rpi-imager
    protonmail-desktop
    libreoffice
  ];
}
