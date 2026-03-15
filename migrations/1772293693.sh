echo "Move single_window_aspect_ratio from dwindle to layout in user looknfeel.conf"

looknfeel="$HOME/.config/hypr/looknfeel.conf"

if [[ -f $looknfeel ]] && grep -q 'single_window_aspect_ratio' "$looknfeel"; then
  # If single_window_aspect_ratio is already in a layout block (and not in dwindle), we're done
  if awk '
    /layout[[:space:]]*{/  { in_layout = 1 }
    /dwindle[[:space:]]*{/ { in_dwindle = 1 }
    /}/                  { in_layout = 0; in_dwindle = 0 }
    /single_window_aspect_ratio/ {
      if (in_layout)   found_in_layout = 1
      if (in_dwindle)  found_in_dwindle = 1
    }
    END {
      if (found_in_layout && !found_in_dwindle) exit 0
      exit 1
    }
  ' "$looknfeel"; then
    exit 0
  fi

  # If the dwindle block contains other settings, we should split it
  if awk '
    /dwindle[[:space:]]*{/ { in_dwindle = 1; block = "" }
    in_dwindle { block = block $0 ORS }
    in_dwindle && /}/ {
      if (block ~ /(pseudotile|preserve_split|force_split)/) { found = 1 }
      in_dwindle = 0
    }
    END { exit !found }
  ' "$looknfeel"; then
    ASPECT_RATIO=$(grep -m1 "single_window_aspect_ratio" "$looknfeel")
    # Remove the aspect ratio line from the current dwindle block
    sed -i "/single_window_aspect_ratio/d" "$looknfeel"
    # Append a separate layout block
    echo -e "\n# https://wiki.hyprland.org/Configuring/Variables/#layout\nlayout {\n    $ASPECT_RATIO\n}" >> "$looknfeel"
  else
    # If no other dwindle settings, just rename the block
    sed -i \
      -e 's|# https://wiki.hyprland.org/Configuring/Dwindle-Layout/|# https://wiki.hyprland.org/Configuring/Variables/#layout|' \
      -e 's|^dwindle {|layout {|' \
      "$looknfeel"
  fi
fi
