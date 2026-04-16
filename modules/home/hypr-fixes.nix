{
  pkgs,
  lib,
  ...
}: {
  # Keep user Hypr configs compatible with current Hyprland syntax.
  # This runs on HM activation so a rebuild can self-heal parser issues
  # without rewriting user keybind files behind their back.
  home.activation.hyprConfigSanityFixes = lib.hm.dag.entryAfter ["writeBoundary"] ''
        set -eu

        GREP="${pkgs.gnugrep}/bin/grep"
        CP="${pkgs.coreutils}/bin/cp"
        SED="${pkgs.gnused}/bin/sed"
        AWK="${pkgs.gawk}/bin/awk"
        MV="${pkgs.coreutils}/bin/mv"
        CAT="${pkgs.coreutils}/bin/cat"
        CHMOD="${pkgs.coreutils}/bin/chmod"
        FIND="${pkgs.findutils}/bin/find"

        cfg_dir="$HOME/.config/hypr/configs"
        wr="$cfg_dir/WindowRules.conf"
        wr_pre53="$cfg_dir/WindowRules-pre-53.conf"
        wr_v3="$cfg_dir/WindowRules-config-v3.conf"
        ss="$cfg_dir/SystemSettings.conf"
        startup="$cfg_dir/Startup_Apps.conf"
        lock_script="$HOME/.config/hypr/scripts/LockScreen.sh"
        hypridle_conf="$HOME/.config/hypr/hypridle.conf"

        if [ -d "$cfg_dir" ]; then
          if [ -f "$wr" ] && [ -f "$wr_pre53" ] && "$GREP" -q '^windowrule[[:space:]]*=[[:space:]]*match:' "$wr"; then
            "$CP" "$wr" "$wr.bak-hm-autofix" || true
            "$CP" "$wr_pre53" "$wr"
          fi

          if [ -f "$wr" ]; then
            "$SED" -E -i 's/tag:\+/tag +/g' "$wr"
          fi

          if [ -f "$ss" ]; then
            "$SED" -E -i '/^[[:space:]]*on_focus_under_fullscreen[[:space:]]*=.*/d' "$ss"
          fi

          if [ -f "$wr_v3" ]; then
            if ! "$GREP" -q 'match:class ^(teams-pwa)$, tag:+im' "$wr_v3"; then
              "$CAT" >> "$wr_v3" <<'WREOF'
    windowrule = match:class ^(teams-pwa)$, tag:+im
    windowrule = match:class ^(teams-pwa)$, opacity 0.94 0.86
    windowrule = match:class ^(teams-pwa)$ match:title negative:(Microsoft Teams|teams.microsoft.com), float on, center on
    windowrule = match:class ^(teams-pwa)$ match:title ^(Save your password\?|Open Files|Save As|Authentication Required)$, float on, center on, stayfocused
    WREOF
            fi
          fi
        fi

        if [ -f "$startup" ]; then
          "$SED" -i '/^exec-once = ags$/d' "$startup"

          if [ "$("$GREP" -c '^exec-once = qs -c overview  # Quickshell Overview$' "$startup" || true)" -gt 1 ]; then
            "$AWK" '
              $0 == "exec-once = qs -c overview  # Quickshell Overview" {
                if (seen_qs++) next
              }
              { print }
            ' "$startup" > "$startup.tmp"
            "$MV" "$startup.tmp" "$startup"
          fi

          if [ "$("$GREP" -c '^exec-once = blueman-applet$' "$startup" || true)" -gt 1 ]; then
            "$AWK" '
              $0 == "exec-once = blueman-applet" {
                if (seen_blueman++) next
              }
              { print }
            ' "$startup" > "$startup.tmp"
            "$MV" "$startup.tmp" "$startup"
          fi
        fi

        kb="$cfg_dir/Keybinds.conf"
        user_kb="$HOME/.config/hypr/UserConfigs/UserKeybinds.conf"
        wlogout_layout="$HOME/.config/wlogout/layout"
        hypr_scripts_dir="$HOME/.config/hypr/scripts"
        power_script="$hypr_scripts_dir/NHLPowerMenuAction.sh"
        waybar_dir="$HOME/.config/waybar"
        waybar_modules_custom="$waybar_dir/ModulesCustom"
        waybar_modules="$waybar_dir/Modules"

        if [ -d "$hypr_scripts_dir" ]; then
          "$CAT" > "$power_script" <<'POWEREOF'
    #!/usr/bin/env bash
    set -eu

    action="''${1:-menu}"

    show_auth_prompt() {
      local title="$1"
      local body="$2"

      if command -v yad >/dev/null 2>&1; then
        yad \
          --center \
          --on-top \
          --width=460 \
          --title="$title" \
          --window-icon=system-shutdown \
          --image=dialog-password \
          --question \
          --text="$body" \
          --button="Cancel:1" \
          --button="Continue:0"
        return $?
      fi

      return 0
    }

    case "$action" in
      menu)
        exec "$HOME/.config/hypr/scripts/Wlogout.sh"
        ;;
      lock)
        exec "$HOME/.config/hypr/scripts/LockScreen.sh"
        ;;
      logout)
        show_auth_prompt \
          "Confirm logout" \
          "You're about to log out.\n\nIf an authentication prompt appears next, present your fingerprint right away or enter your password.\n\nContinue?"
        exec hyprctl dispatch exit 0
        ;;
      reboot)
        show_auth_prompt \
          "Confirm reboot" \
          "Reboot needs authentication on this system.\n\nPress Continue, then present your fingerprint immediately or enter your password in the next prompt.\n\nContinue?"
        exec sh -c 'loginctl reboot || systemctl reboot'
        ;;
      shutdown|poweroff)
        show_auth_prompt \
          "Confirm shutdown" \
          "Shutdown needs authentication on this system.\n\nPress Continue, then present your fingerprint immediately or enter your password in the next prompt.\n\nContinue?"
        exec sh -c 'loginctl poweroff || systemctl poweroff'
        ;;
      suspend)
        exec sh -c 'loginctl suspend-then-hibernate || systemctl suspend-then-hibernate || loginctl hybrid-sleep || systemctl hybrid-sleep || loginctl suspend || systemctl suspend'
        ;;
      hibernate)
        exec sh -c 'loginctl hibernate || systemctl hibernate'
        ;;
      *)
        echo "Unknown power action: $action" >&2
        exit 1
        ;;
    esac
    POWEREOF
          "$CHMOD" +x "$power_script"
        fi

        for bind_file in "$kb" "$user_kb"; do
          [ -f "$bind_file" ] || continue
          "$SED" -E -i '/^# Open default terminal$/d' "$bind_file"
          "$SED" -E -i '/^bindd?[[:space:]]*=[[:space:]]*\$mainMod[[:space:]]*,[[:space:]]*(RETURN|Return)[[:space:]]*,[[:space:]]*open terminal,[[:space:]]*exec,[[:space:]]*\$term$/d' "$bind_file"
        done

        if [ -f "$user_kb" ]; then
          "$SED" -E -i '/^bindd?[[:space:]]*=[[:space:]]*\$mainMod[[:space:]]*,[[:space:]]*T[[:space:]]*,[[:space:]]*open terminal,[[:space:]]*exec,[[:space:]]*\$term$/d' "$user_kb"

          "$AWK" -F',' '
            function trim(s) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
              return s
            }
            function combo_from_line(line,   rhs, parts, mods, key) {
              sub(/[[:space:]]*#.*/, "", line)
              if (line !~ /^[[:space:]]*(bind[a-z]*|unbind)[[:space:]]*=/) return ""
              split(line, arr, "=")
              rhs = arr[2]
              split(rhs, parts, ",")
              if (length(parts) < 2) return ""
              mods = trim(parts[1]); gsub(/[[:space:]]+/, "", mods)
              key = trim(parts[2]); gsub(/[[:space:]]+/, "", key)
              return mods "," key
            }
            FNR == NR {
              if ($0 ~ /^[[:space:]]*bind[a-z]*[[:space:]]*=/) {
                combo = combo_from_line($0)
                if (combo != "") defaults[combo] = 1
              }
              next
            }
            {
              if ($0 ~ /^[[:space:]]*unbind[[:space:]]*=/) {
                combo = combo_from_line($0)
                if (combo != "") unbound[combo] = 1
                print
                next
              }
              if ($0 ~ /^[[:space:]]*bind[a-z]*[[:space:]]*=/) {
                combo = combo_from_line($0)
                if (combo != "" && defaults[combo] && !unbound[combo]) next
              }
              print
            }
          ' "$kb" "$user_kb" > "$user_kb.tmp"
          "$MV" "$user_kb.tmp" "$user_kb"
        fi

        if [ -f "$kb" ]; then
          if [ "$("$GREP" -c '^bindd = \$mainMod, T, open terminal, exec, \$term$' "$kb" || true)" -gt 1 ]; then
            "$AWK" '
              $0 == "bindd = $mainMod, T, open terminal, exec, $term" {
                if (seen_terminal++) next
              }
              { print }
            ' "$kb" > "$kb.tmp"
            "$MV" "$kb.tmp" "$kb"
          fi

          if ! "$GREP" -q '^bindd = \$mainMod, T, open terminal, exec, \$term$' "$kb"; then
            printf '
    # Open default terminal
    bindd = $mainMod, T, open terminal, exec, $term
    ' >> "$kb"
          fi
        fi

        if [ -f "$kb" ] && [ -f "$user_kb" ]; then
          if ! "$GREP" -Eq '^[[:space:]]*bindd?[[:space:]]*=[[:space:]]*\$mainMod[[:space:]]+SHIFT,[[:space:]]*C,[[:space:]]*.*pavucontrol' "$kb" &&
             ! "$GREP" -Eq '^[[:space:]]*bindd?[[:space:]]*=[[:space:]]*\$mainMod[[:space:]]+SHIFT,[[:space:]]*C,[[:space:]]*.*pavucontrol' "$user_kb"; then
            printf '\n# Open volume control\nbindd = $mainMod SHIFT, C, volume control, exec, pavucontrol\n' >> "$user_kb"
          fi
        fi

        if [ -f "$wlogout_layout" ]; then
          "$SED" -i 's#"$HOME/.config/hypr/scripts/LockScreen.sh"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh lock"#' "$wlogout_layout"
          "$SED" -i 's#"loginctl reboot || systemctl reboot"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh reboot"#' "$wlogout_layout"
          "$SED" -i 's#"systemctl reboot"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh reboot"#' "$wlogout_layout"
          "$SED" -i 's#"loginctl poweroff || systemctl poweroff"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh shutdown"#' "$wlogout_layout"
          "$SED" -i 's#"systemctl poweroff"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh shutdown"#' "$wlogout_layout"
          "$SED" -i 's#"hyprctl dispatch exit 0"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh logout"#' "$wlogout_layout"
          "$SED" -i 's#"loginctl suspend || systemctl suspend"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh suspend"#' "$wlogout_layout"
          "$SED" -i 's#"systemctl suspend"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh suspend"#' "$wlogout_layout"
          "$SED" -i 's#"loginctl hibernate || systemctl hibernate"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh hibernate"#' "$wlogout_layout"
          "$SED" -i 's#"systemctl hibernate"#"$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh hibernate"#' "$wlogout_layout"
        fi

        if [ -f "$waybar_modules_custom" ]; then
          "$SED" -i 's#"on-click": "\$HOME/.config/hypr/scripts/Wlogout.sh"#"on-click": "\$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh menu"#' "$waybar_modules_custom"
          "$SED" -i 's#"on-click-right": "\$HOME/.config/hypr/scripts/ChangeBlur.sh"#"on-click-right": "\$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh menu"#' "$waybar_modules_custom"
          "$SED" -i 's#Left Click: Logout Menu\\nRight Click: Change Blur#Left Click: Power menu\\nRight Click: Power menu#' "$waybar_modules_custom"
        fi

        if [ -f "$waybar_modules" ]; then
          "$SED" -i 's#"tooltip-format-activated": "Idle_inhibitor active"#"tooltip-format-activated": "Coffee mode active"#' "$waybar_modules"
          "$SED" -i 's#"tooltip-format-deactivated": "Idle_inhibitor not active"#"tooltip-format-deactivated": "Coffee mode inactive"#' "$waybar_modules"
          "$SED" -i 's#"activated": " "#"activated": " "#' "$waybar_modules"
          "$SED" -i 's#"deactivated": " "#"deactivated": "󰾪 "#' "$waybar_modules"
        fi

        if [ -d "$waybar_dir/configs" ]; then
          while IFS= read -r cfg; do
            "$SED" -i 's#"on-click-right": "\$HOME/.config/hypr/scripts/Wlogout.sh"#"on-click-right": "\$HOME/.config/hypr/scripts/NHLPowerMenuAction.sh menu"#' "$cfg"
          done < <("$FIND" "$waybar_dir/configs" -maxdepth 1 -type f)
        fi

        if [ -f "$hypridle_conf" ]; then
          "$CP" "$hypridle_conf" "$hypridle_conf.bak-hm-autofix" || true
          "$CAT" > "$hypridle_conf" <<'HYPRIDLEEOF'
    # Managed by Home Manager activation fixups in this repo.

    $iDIR="$HOME/.config/swaync/images/ja.png"

    general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch dpms on
        ignore_dbus_inhibit = false
    }

    listener {
        timeout = 35
        on-timeout = sh -c 'brightnessctl -s set 15%'
        on-resume = sh -c 'brightnessctl -r || brightnessctl set 100%'
    }

    listener {
        timeout = 120
        on-timeout = hyprctl dispatch dpms off
        on-resume = sh -c 'hyprctl dispatch dpms on; brightnessctl -r || brightnessctl set 100%'
    }

    listener {
        timeout = 600
        on-timeout = loginctl lock-session
    }
    HYPRIDLEEOF
        fi

        if [ -f "$lock_script" ]; then
          "$CAT" > "$lock_script" <<'LOCKEOF'
    #!/usr/bin/env bash
    set -eu

    if ! pidof hyprlock >/dev/null 2>&1; then
      hyprlock >/dev/null 2>&1 &
    fi

    loginctl lock-session >/dev/null 2>&1 || true

    if [ -x "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" ]; then
      "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1 &
    fi
    LOCKEOF
          "$CHMOD" +x "$lock_script"
        fi
  '';
}
