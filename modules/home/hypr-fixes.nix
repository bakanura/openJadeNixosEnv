{ pkgs, lib, ... }: {
  # Keep user Hypr configs compatible with current Hyprland syntax.
  # This runs on HM activation so a rebuild can self-heal parser issues
  # without rewriting user keybind files behind their back.
  home.activation.hyprConfigSanityFixes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    GREP="${pkgs.gnugrep}/bin/grep"
    CP="${pkgs.coreutils}/bin/cp"
    SED="${pkgs.gnused}/bin/sed"
    AWK="${pkgs.gawk}/bin/awk"
    MV="${pkgs.coreutils}/bin/mv"
    CAT="${pkgs.coreutils}/bin/cat"
    CHMOD="${pkgs.coreutils}/bin/chmod"

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
      "$SED" -i 's#"action" : "systemctl reboot"#"action" : "loginctl reboot || systemctl reboot"#' "$wlogout_layout"
      "$SED" -i 's#"action" : "systemctl poweroff"#"action" : "loginctl poweroff || systemctl poweroff"#' "$wlogout_layout"
      "$SED" -i 's#"action" : "systemctl suspend"#"action" : "loginctl suspend || systemctl suspend"#' "$wlogout_layout"
      "$SED" -i 's#"action" : "systemctl hibernate"#"action" : "loginctl hibernate || systemctl hibernate"#' "$wlogout_layout"
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