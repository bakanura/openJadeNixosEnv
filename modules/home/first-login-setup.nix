{pkgs, ...}: let
  logoUrl = "https://risiq.de/wp-content/uploads/2026/02/logo-icon-01.svg";
  setupFlow = pkgs.writeShellScript "nhl-first-login-setup-flow" ''
        set -euo pipefail

        current_user="$(id -un)"
        marker="$HOME/.local/state/nhl-first-login-setup.done"
        mkdir -p "$(dirname "$marker")"

        if [ -f "$marker" ]; then
          exit 0
        fi

        echo "==============================================="
        echo "        NixOS Device First Login / Erstanmeldung"
        echo "==============================================="

        rendered_logo=0
        if command -v curl >/dev/null 2>&1 && command -v rsvg-convert >/dev/null 2>&1 && command -v chafa >/dev/null 2>&1; then
          tmpdir="$(mktemp -d)"
          if curl -fsSL "${logoUrl}" -o "$tmpdir/logo.svg" 2>/dev/null; then
            if rsvg-convert -w 96 -h 28 "$tmpdir/logo.svg" 2>/dev/null | chafa -f symbols -c none --symbols ascii --size 52x14 - 2>/dev/null; then
              rendered_logo=1
            fi
          fi
          rm -rf "$tmpdir"
        fi

        if [ "$rendered_logo" -ne 1 ]; then
          cat <<'EOF'
          _   _ _      ___  ____  
         | \ | (_)_  _/ _ \/ ___| 
         |  \| | \ \/ / | | \___ \ 
         | |\  | |>  <| |_| |___) |
         |_| \_|_/_/\_\\___/|____/ 
EOF
        fi
        echo "Logo (SVG): ${logoUrl}"
        echo "Support / Support-Hotline: 00496214909053-3"
        echo

        echo "Welcome to NixOS."
        echo "Willkommen bei NixOS."
        echo "This one-time setup secures your account."
        echo "Diese einmalige Einrichtung sichert Ihr Benutzerkonto."
        echo
        echo "1) Change your login password / Login-Passwort ändern (required / erforderlich)"
        echo "2) Enroll your fingerprint / Fingerabdruck einrichten (required / erforderlich)"
        echo

        if [ "$current_user" = "nixos-bootstrap" ]; then
          echo "Bootstrap mode detected."
          echo "Einrichtungsmodus erkannt."
          echo

          target_user=""
          while [ -z "$target_user" ]; do
            read -r -p "Enter your desired username / Gewünschten Benutzernamen eingeben: " target_user
            if ! echo "$target_user" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
              echo "Invalid username format."
              echo "Ungültiges Benutzerformat."
              target_user=""
              continue
            fi
            if id "$target_user" >/dev/null 2>&1; then
              echo "User already exists."
              echo "Benutzer existiert bereits."
              target_user=""
            fi
          done

          echo "Creating user '$target_user'..."
          sudo useradd -m -s /run/current-system/sw/bin/zsh -G networkmanager,wheel,libvirtd,scanner,lp,video,input,audio "$target_user"

          echo "Set password for '$target_user' now."
          sudo passwd "$target_user"

          repo="$HOME/NixOS-Hyprland"
          host_name="$(hostnamectl --static 2>/dev/null || cat /etc/hostname)"
          identity_file="$repo/hosts/$host_name/identity.json"
          if [ -f "$repo/flake.nix" ]; then
            echo "Updating host identity to '$target_user'..."
            sudo mkdir -p "$(dirname "$identity_file")"
            sudo tee "$identity_file" >/dev/null <<EOF
    {
      "username": "$target_user"
    }
EOF
          fi

          echo
          echo "You can now log out and sign in as '$target_user'."
          echo "Sie können sich jetzt abmelden und als '$target_user' anmelden."
          echo
          echo "Optional cleanup command (run after new user login):"
          echo "  sudo userdel -r nixos-bootstrap"
          read -r -p "Press Enter to close / Enter zum Schließen..."
          touch "$marker"
          exit 0
        fi

        echo
        echo "Password change is required on first login."
        echo "Passwortänderung ist beim ersten Login erforderlich."
        while true; do
          if passwd; then
            break
          fi
          echo "[WARN] Password change did not complete. Please try again."
        done

        if command -v fprintd-enroll >/dev/null 2>&1; then
          echo
          echo "Fingerprint enrollment is required on first login."
          echo "Fingerabdruck-Einrichtung ist beim ersten Login erforderlich."
          while true; do
            if fprintd-enroll; then
              echo "[OK] Fingerprint enrollment completed."
              break
            fi

            echo
            echo "[WARN] Fingerprint enrollment did not complete."
            echo "[WARN] Retrying... Please place your finger when prompted."
          done
        else
          echo "[ERROR] fprintd-enroll is not available. Cannot finish required first-login setup."
          echo "[ERROR] fprintd-enroll ist nicht verfügbar. Erforderliche Ersteinrichtung kann nicht abgeschlossen werden."
          read -r -p "Press Enter to close / Enter zum Schließen..."
          exit 1
        fi

        # If bootstrap account still exists and we are now logged in as the real user,
        # remove it automatically after successful handoff.
        if [ "$current_user" != "nixos-bootstrap" ] && id nixos-bootstrap >/dev/null 2>&1; then
          echo -e "\n[INFO] Finalizing setup: cleaning up bootstrap account 'nixos-bootstrap'..."

          # Forcefully terminate any lingering bootstrap processes or systemd units to allow deletion.
          bootstrap_uid=$(id -u nixos-bootstrap 2>/dev/null || true)
          if [ -n "$bootstrap_uid" ]; then
            sudo systemctl stop "user@$bootstrap_uid.service" 2>/dev/null || true
          fi
          sudo pkill -u nixos-bootstrap || true
          echo "[INFO] Requesting administrative access to delete bootstrap user..."
          # Wait a moment for processes to terminate
          if sudo userdel --force --remove nixos-bootstrap; then
            echo "[INFO] Bootstrap account and home directory have been removed."
          else
            echo "[WARN] Automatic removal of 'nixos-bootstrap' failed (exit code $?)."
            echo "[WARN] You can try manually: sudo userdel -rf nixos-bootstrap"
          fi
        fi

        touch "$marker"
        echo
        echo "NixOS first-login setup complete."
        echo "NixOS-Erstanmeldung abgeschlossen."
        read -r -p "Press Enter to close / Enter zum Schließen..."
  '';

  launcher = pkgs.writeShellScript "nhl-first-login-setup-launcher" ''
    set -euo pipefail

    marker="$HOME/.local/state/nhl-first-login-setup.done"
    mkdir -p "$(dirname "$marker")"

    if [ -f "$marker" ]; then
      exit 0
    fi

    if command -v nhl-open-terminal >/dev/null 2>&1; then
      nhl-open-terminal -e "${setupFlow}" || nhl-open-terminal "${setupFlow}"
      exit 0
    fi

    if command -v ghostty >/dev/null 2>&1; then
      ghostty -e "${setupFlow}" || ghostty "${setupFlow}"
      exit 0
    fi

    if command -v kitty >/dev/null 2>&1; then
      kitty --title "NixOS First Login Setup" -e "${setupFlow}"
      exit 0
    fi

    if command -v notify-send >/dev/null 2>&1; then
      notify-send "NixOS First Login Setup" "Run: ${setupFlow}"
    fi
  '';
in {
  systemd.user.services.nhl-first-login-setup = {
    Unit = {
      Description = "NixOS one-time first-login account setup";
      After = ["graphical-session.target"];
      Wants = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${launcher}";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
