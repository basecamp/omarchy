echo "Move single_window_aspect_ratio from dwindle to layout in user looknfeel.conf"

looknfeel="$HOME/.config/hypr/looknfeel.conf"

if [[ -f $looknfeel ]] && grep -q 'single_window_aspect_ratio' "$looknfeel"; then
  # If it's already in a layout block, we're done
  if grep -q '^layout {' "$looknfeel"; then
    exit 0
  fi

  # If the block contains dwindle-specific settings, we should split it
  if grep -qE "pseudotile|preserve_split|force_split" "$looknfeel"; then
    ASPECT_RATIO=$(grep "single_window_aspect_ratio" "$looknfeel")
    # Remove the aspect ratio line from the current dwindle block
    sed -i "/single_window_aspect_ratio/d" "$looknfeel"
    # Append a separate layout block
    echo -e "\n# https://wiki.hyprland.org/Configuring/Variables/#layout\nlayout {\n    $ASPECT_RATIO\n}" >> "$looknfeel"
  else
    # If no other dwindle settings, just rename the block
    sed -i \
      -e 's|# https://wiki.hypr.land/Configuring/Dwindle-Layout/|# https://wiki.hyprland.org/Configuring/Variables/#layout|' \
      -e 's|# https://wiki.hyprland.org/Configuring/Dwindle-Layout/|# https://wiki.hyprland.org/Configuring/Variables/#layout|' \
      -e 's|^dwindle {|layout {|' \
      "$looknfeel"
  fi
fi
