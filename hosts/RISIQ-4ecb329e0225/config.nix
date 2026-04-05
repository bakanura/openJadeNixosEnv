# Project source: https://github.com/JaKooLit/NixOS-Hyprland
# Main default config
{
  lib,
  pkgs,
  host,
  username,
  options,
  config,
  ...
}: let
  inherit (import ./variables.nix) keyboardLayout;
  deeplSecretFile = ../../secrets/${host}/deepl-api-key.age;
  clamshellLidHelper = pkgs.writeShellApplication {
    name = "clamshell-lid";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.jq
      pkgs.systemd
      pkgs.usbguard
      pkgs.hyprland
    ];
    text = ''
      set -eu

      state_file="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/clamshell-lid.state"
      last_mode="unknown"

      live_allowed_dock_present() {
        usbguard list-devices 2>/dev/null           | ${pkgs.gawk}/bin/awk '
              $2 == "allow" { print tolower($0) }
            '           | ${pkgs.gnugrep}/bin/grep -Eq '
              with-connect-type "(hotplug|unknown)".*(name ".*(dock|docking|hub|billboard|displaylink|ethernet|card reader)"|with-interface \{?([^}]*09:|[^}]*11:|[^}]*02:06:00|[^}]*0a:|[^}]*08:06:50))
            '
      }

      lid_state() {
        for state_path in /proc/acpi/button/lid/*/state; do
          [ -r "$state_path" ] || continue
          if grep -qi 'closed' "$state_path"; then
            echo "closed"
            return
          fi
          if grep -qi 'open' "$state_path"; then
            echo "open"
            return
          fi
        done
        echo "open"
      }

      external_monitor_count() {
        hyprctl -j monitors 2>/dev/null | jq '[.[] | select(.name != "eDP-1")] | length' 2>/dev/null || echo "0"
      }

      while true; do
        lid="$(lid_state)"
        external_count="$(external_monitor_count)"
        mode="normal"
        dock_present="0"

        if live_allowed_dock_present; then
          dock_present="1"
        fi

        if [ "$lid" = "closed" ]; then
          if [ "''${external_count:-0}" -gt 0 ]; then
            mode="clamshell"
          else
            mode="suspend"
          fi
        fi

        if [ "$mode" != "$last_mode" ]; then
          if [ "$mode" = "clamshell" ]; then
            hyprctl keyword monitor "eDP-1,disable" >/dev/null 2>&1 || true
          elif [ "$mode" = "suspend" ]; then
            hyprctl keyword monitor "eDP-1,preferred,auto,1" >/dev/null 2>&1 || true
            loginctl suspend >/dev/null 2>&1 || systemctl suspend >/dev/null 2>&1 || true
          else
            hyprctl keyword monitor "eDP-1,preferred,auto,1" >/dev/null 2>&1 || true
          fi
          printf 'mode=%s external=%s dock=%s\n' "$mode" "$external_count" "$dock_present" > "$state_file" || true
          last_mode="$mode"
        fi

        sleep 2
      done
    '';
  };
in {
  imports = [
    ./hardware.nix
    ./users.nix
    ./packages-fonts.nix
    ../../modules/drivers
    ../../modules/hardware
  ];

  # Configure boot settings.
  boot = {
    kernelPackages = pkgs.linuxPackages_zen; # zen Kernel
    #kernelPackages = pkgs.linuxPackages_latest; # Kernel

    kernelParams = [
      "nowatchdog"
      "modprobe.blacklist=sp5100_tco" # watchdog for AMD
      "modprobe.blacklist=iTCO_wdt" # watchdog for Intel
    ];

    # This is for OBS Virtual Cam Support
    #kernelModules = [ "v4l2loopback" ];
    #  extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];

    initrd = {
      systemd.enable = true;
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      kernelModules = lib.optional config.drivers.amdgpu.displaylink.enable "evdi";
      luks.devices."luks-33d9c70f-a90d-4e2b-bbcb-526ff77ada2c" = {
        crypttabExtraOpts = [
          "tpm2-device=auto"
          "tpm2-pcrs=7"
        ];
      };
    };

    # Needed For Some Steam Games
    #kernel.sysctl = {
    #  "vm.max_map_count" = 2147483642;
    #};

    ## BOOT LOADERS: NOTE USE ONLY 1. either systemd or grub
    # Bootloader SystemD
    loader.systemd-boot.enable = true;

    loader.efi = {
      #efiSysMountPoint = "/efi"; #this is if you have separate /efi partition
      canTouchEfiVariables = true;
    };

    loader.timeout = 5;

    # Bootloader GRUB
    #loader.grub = {
    #enable = true;
    #  devices = [ "nodev" ];
    #  efiSupport = true;
    #  gfxmodeBios = "auto";
    #  memtest86.enable = true;
    #  extraGrubInstallArgs = [ "--bootloader-id=${host}" ];
    #  configurationName = "${host}";
    #	 };

    # Bootloader GRUB theme, configure below

    ## -end of BOOTLOADERS----- ##

    # Make /tmp a tmpfs
    tmp = {
      useTmpfs = false;
      tmpfsSize = "30%";
    };

    # Appimage Support
    binfmt.registrations.appimage = {
      wrapInterpreterInShell = false;
      interpreter = "${pkgs.appimage-run}/bin/appimage-run";
      recognitionType = "magic";
      offset = 0;
      mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
      magicOrExtension = ''\x7fELF....AI\x02'';
    };

    plymouth.enable = true;
  };

  # GRUB bootloader theme (requires enabling GRUB above and in flake.nix)
  #distro-grub-themes = {
  #  enable = true;
  #  theme = "nixos";
  #};

  # Configure optional module toggles.
  drivers = {
    amdgpu.enable = true;
    amdgpu.displaylink.enable = false;
    intel.enable = true;
    nvidia.enable = false;
    nvidia-prime = {
      enable = false;
      intelBusID = "";
      nvidiaBusID = "";
    };
  };
  vm.guest-services.enable = false;
  local.hardware-clock.enable = false;
  local.security.fingerprint.enable = true;
  local.security.session.powerButtonUseAcpid = true;
  local.security.session.powerButtonAction = "hybrid-sleep";
  local.security.session.rebootButtonAction = "ignore";
  local.entra.enable = true;
  local.customUiTranslation = {
    enable = true;
    targetLanguage = if keyboardLayout == "de" then "DE" else null;
    apiKeyFile = "/home/${username}/.config/deepl-api-key";
    encryptedApiKeyFile = if builtins.pathExists deeplSecretFile then deeplSecretFile else null;
  };

  security.tpm2.enable = true;

  # Configure networking.
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      wifi.powersave = false;
      dispatcherScripts = [
        {
          type = "basic";
          source = pkgs.writeShellScript "prefer-wired-eth0" ''
            set -eu

            interface="$1"
            status="$2"
            wired_if="eth0"
            wifi_if="wlp1s0"
            nmcli_bin="${pkgs.networkmanager}/bin/nmcli"

            [ "$interface" = "$wired_if" ] || exit 0

            case "$status" in
              up|dhcp4-change|connectivity-change)
                "$nmcli_bin" device disconnect "$wifi_if" >/dev/null 2>&1 || true
                ;;
              down|pre-down)
                "$nmcli_bin" device connect "$wifi_if" >/dev/null 2>&1 || true
                ;;
            esac
          '';
        }
      ];
    };
    hostName = "${host}";
    timeServers = options.networking.timeServers.default ++ ["pool.ntp.org"];
  };

  # Set your time zone.
  services.automatic-timezoned.enable = false; # based on IP location
  services.resolved.enable = true;

  #https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Configure system services.
  services = {
    xserver = {
      enable = false;
      xkb = {
        layout = "${keyboardLayout}";
        variant = "";
      };
    };

    smartd = {
      enable = false;
      autodetect = true;
    };

    gvfs.enable = true;
    tumbler.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    #pulseaudio.enable = false; #unstable
    udev = {
      enable = true;
      extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="AC*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="risiq-acoustic-power-policy.service"
        ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="ADP*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="risiq-acoustic-power-policy.service"
      '';
    };
    envfs.enable = true;
    dbus.enable = true;

    fstrim = {
      enable = true;
      interval = "weekly";
    };

    libinput.enable = true;

    rpcbind.enable = true;
    nfs.server.enable = true;

    openssh.enable = true;
    flatpak.enable = true;

    blueman.enable = true;

    #hardware.openrgb.enable = true;
    #hardware.openrgb.motherboard = "amd";

    fwupd.enable = true;

    upower.enable = true;

    gnome.gnome-keyring.enable = true;

    #printing = {
    #  enable = false;
    #  drivers = [
    # pkgs.hplipWithPlugin
    #  ];
    #};

    #avahi = {
    #  enable = true;
    #  nssmdns4 = true;
    #  openFirewall = true;
    #};

    #ipp-usb.enable = true;

    #syncthing = {
    #  enable = false;
    #  user = "${username}";
    #  dataDir = "/home/${username}";
    #  configDir = "/home/${username}/.config/syncthing";
    #};
  };

  systemd.services.flatpak-repo = {
    path = [pkgs.flatpak];
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };

  systemd.services.risiq-acoustic-power-policy = {
    description = "Apply quieter CPU/power policy, especially on AC";
    after = ["power-profiles-daemon.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -eu

      ac_online=0
      for f in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
        [ -r "$f" ] || continue
        v="$(cat "$f" 2>/dev/null || true)"
        if [ "$v" = "1" ]; then
          ac_online=1
          break
        fi
      done

      # Keep profile off "performance" so plugging AC doesn't instantly ramp fan/noise.
      if command -v ${pkgs.power-profiles-daemon}/bin/powerprofilesctl >/dev/null 2>&1; then
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced >/dev/null 2>&1 || true
      fi

      if [ -w /sys/devices/system/cpu/amd_pstate/max_perf_pct ]; then
        # Keep a calmer baseline on AC, and prioritize battery life when unplugged.
        if [ "$ac_online" = "1" ]; then
          echo 65 > /sys/devices/system/cpu/amd_pstate/max_perf_pct || true
        else
          echo 55 > /sys/devices/system/cpu/amd_pstate/max_perf_pct || true
        fi
      fi

      if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
        # Baseline starts with boost off; adaptive service enables it on-demand on AC.
        if [ "$ac_online" = "1" ]; then
          echo 0 > /sys/devices/system/cpu/cpufreq/boost || true
        else
          # Battery lifetime first.
          echo 0 > /sys/devices/system/cpu/cpufreq/boost || true
        fi
      fi
    '';
  };

  systemd.services.risiq-adaptive-cpu-boost = {
    description = "Adaptive CPU boost controller (AC-only, battery-priority)";
    after = ["risiq-acoustic-power-policy.service"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -eu

      state_file="/run/risiq-adaptive-boost.state"
      last_state="off"
      if [ -r "$state_file" ]; then
        last_state="$(cat "$state_file" 2>/dev/null || true)"
      fi

      ac_online=0
      for f in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
        [ -r "$f" ] || continue
        v="$(cat "$f" 2>/dev/null || true)"
        if [ "$v" = "1" ]; then
          ac_online=1
          break
        fi
      done

      # Battery: keep strict power-saving.
      if [ "$ac_online" != "1" ]; then
        if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
          echo 0 > /sys/devices/system/cpu/cpufreq/boost || true
        fi
        if [ -w /sys/devices/system/cpu/amd_pstate/max_perf_pct ]; then
          echo 55 > /sys/devices/system/cpu/amd_pstate/max_perf_pct || true
        fi
        echo "off" > "$state_file"
        exit 0
      fi

      # AC: adaptive boost based on sustained CPU demand with hysteresis.
      read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
      total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
      idle1=$((idle + iowait))
      sleep 1
      read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2 < /proc/stat
      total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
      idle2t=$((idle2 + iowait2))

      delta_total=$((total2 - total1))
      delta_idle=$((idle2t - idle1))
      util=0
      if [ "$delta_total" -gt 0 ]; then
        util=$(( (100 * (delta_total - delta_idle)) / delta_total ))
      fi

      load1="$(cut -d' ' -f1 /proc/loadavg | tr -d '\n' || true)"
      # convert "3.43" -> 343 (integer hundredths) without fragile quoting
      load1_int="$(printf "%s\n" "''${load1:-0}" | ${pkgs.gawk}/bin/awk '{ printf "%d", ($1 * 100) }')"
      cpus="$(nproc)"
      high_load=$((cpus * 90))
      low_load=$((cpus * 45))

      # Enable threshold: util >= 70% or load >= 0.90 per CPU.
      # Disable threshold: util <= 35% and load <= 0.45 per CPU.
      if [ "$util" -ge 70 ] || [ "$load1_int" -ge "$high_load" ]; then
        target="on"
      elif [ "$util" -le 35 ] && [ "$load1_int" -le "$low_load" ]; then
        target="off"
      else
        target="$last_state"
      fi

      if [ "$target" = "on" ]; then
        if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
          echo 1 > /sys/devices/system/cpu/cpufreq/boost || true
        fi
        if [ -w /sys/devices/system/cpu/amd_pstate/max_perf_pct ]; then
          echo 100 > /sys/devices/system/cpu/amd_pstate/max_perf_pct || true
        fi
      else
        if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
          echo 0 > /sys/devices/system/cpu/cpufreq/boost || true
        fi
        if [ -w /sys/devices/system/cpu/amd_pstate/max_perf_pct ]; then
          echo 65 > /sys/devices/system/cpu/amd_pstate/max_perf_pct || true
        fi
      fi

      echo "$target" > "$state_file"
    '';
  };

  systemd.user.services.clamshell-lid = {
    description = "Hyprland clamshell behavior for docked monitor setups";
    after = ["graphical-session.target"];
    wantedBy = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "2s";
      ExecStart = "${clamshellLidHelper}/bin/clamshell-lid";
    };
  };

  systemd.timers.risiq-adaptive-cpu-boost = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15s";
      Unit = "risiq-adaptive-cpu-boost.service";
    };
  };

  # zram
  zramSwap = {
    enable = true;
    priority = 100;
    memoryPercent = 30;
    swapDevices = 1;
    algorithm = "zstd";
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "schedutil";
  };

  local.power.fanCurve = {
    enable = true;
    defaultStrategy = "quiet";
    strategyOnDischarging = "quiet";
  };

  #hardware.sane = {
  #  enable = true;
  #  extraBackends = [ pkgs.sane-airscan ];
  #  disabledDefaultBackends = [ "escl" ];
  #};

  # Extra Logitech Support
  hardware = {
    logitech.wireless.enable = false;
    logitech.wireless.enableGraphical = false;
  };

  services.pulseaudio.enable = false; # stable branch

  # Bluetooth
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
          Experimental = true;
        };
      };
    };
  };

  # Security / Polkit
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    polkit.extraConfig = ''
       polkit.addRule(function(action, subject) {
         if (
           subject.isInGroup("users")
             && (
               action.id == "org.freedesktop.login1.reboot" ||
               action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
               action.id == "org.freedesktop.login1.power-off" ||
               action.id == "org.freedesktop.login1.power-off-multiple-sessions"
             )
           )
         {
           return polkit.Result.YES;
         }
      })
    '';
  };
  security.pam.services.swaylock = {
    text = ''
      auth include login
    '';
  };

  # Cachix, Optimization settings and garbage collection automation
  nix = {
    settings = {
      auto-optimise-store = true;
      warn-dirty = false;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = ["https://hyprland.cachix.org"];
      trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Virtualization / Containers
  virtualisation.libvirtd.enable = false;
  virtualisation.podman = {
    enable = false;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = false;
  };

  # OpenGL
  hardware.graphics = {
    enable = true;
  };

  console.keyMap = "de";

  # For Electron apps to use wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  # For Hyprland QT Support
  environment.sessionVariables.QML_IMPORT_PATH = "${pkgs.hyprland-qt-support}/lib/qt-6/qml";

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, such as file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first installation of this system.
  # Before changing this value, read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  time.timeZone = "Europe/Berlin";
  system.stateVersion = "24.11"; # Did you read the comment?
}
