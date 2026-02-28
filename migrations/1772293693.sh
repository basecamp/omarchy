echo "Rename dwindle section to layout in user looknfeel.conf"

looknfeel="$HOME/.config/hypr/looknfeel.conf"

if [[ -f $looknfeel ]] && grep -q 'single_window_aspect_ratio' "$looknfeel"; then
  sed -i \
    -e 's|# https://wiki.hypr.land/Configuring/Dwindle-Layout/|# https://wiki.hypr.land/Configuring/Variables/#layout|' \
    -e 's|^dwindle {|layout {|' \
    "$looknfeel"
fi
