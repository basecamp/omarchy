echo "Fix looknfeel.conf: Restore dwindle block and separate layout block for single_window_aspect_ratio"

looknfeel="$HOME/.config/hypr/looknfeel.conf"

if [[ -f $looknfeel ]] && grep -q '^layout {' "$looknfeel"; then
  # If the layout block contains dwindle-specific settings, it's the broken state
  if grep -qE "pseudotile|preserve_split|force_split" "$looknfeel"; then
    # 1. Rename layout back to dwindle
    sed -i 's|^layout {|dwindle {|' "$looknfeel"
    
    # 2. Extract single_window_aspect_ratio if present
    if grep -q "single_window_aspect_ratio" "$looknfeel"; then
      ASPECT_RATIO=$(grep "single_window_aspect_ratio" "$looknfeel")
      sed -i "/single_window_aspect_ratio/d" "$looknfeel"
      echo -e "\n# https://wiki.hyprland.org/Configuring/Variables/#layout\nlayout {\n    $ASPECT_RATIO\n}" >> "$looknfeel"
    fi
  fi
fi
