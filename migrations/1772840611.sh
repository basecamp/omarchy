echo "Fix looknfeel.conf: Restore dwindle block and separate layout block for single_window_aspect_ratio"

looknfeel="$HOME/.config/hypr/looknfeel.conf"

if [[ -f $looknfeel ]] && grep -q '^layout {' "$looknfeel"; then
  # If a layout block itself contains dwindle-specific settings, it's the broken state
  if awk '
    /^layout[[:space:]]*{/ { in_layout = 1; block = "" }
    in_layout { block = block $0 ORS }
    in_layout && /^}/ {
      if (block ~ /(pseudotile|preserve_split|force_split)/) { found = 1 }
      in_layout = 0
    }
    END { exit !found }
  ' "$looknfeel"; then
    # 1. Rename layout back to dwindle
    sed -i 's|^layout {|dwindle {|' "$looknfeel"
    
    # 2. Extract single_window_aspect_ratio specifically from this now-dwindle block if present
    if grep -q "single_window_aspect_ratio" "$looknfeel"; then
      ASPECT_RATIO=$(grep -m1 "single_window_aspect_ratio" "$looknfeel")
      sed -i "/single_window_aspect_ratio/d" "$looknfeel"
      echo -e "\n# https://wiki.hyprland.org/Configuring/Variables/#layout\nlayout {\n    $ASPECT_RATIO\n}" >> "$looknfeel"
    fi
  fi
fi
