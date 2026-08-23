echo "Apply a desktop mode from each display's EDID on every graphical session"

unit_src="${OMARCHY_PATH:-/usr/share/omarchy}/default/systemd/user/omarchy-hyprland-monitor-apply.service"
unit_dst="$HOME/.config/systemd/user/omarchy-hyprland-monitor-apply.service"

if [[ -f $unit_src ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp -f "$unit_src" "$unit_dst"
  systemctl --user daemon-reload
  systemctl --user enable omarchy-hyprland-monitor-apply.service
  if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start omarchy-hyprland-monitor-apply.service
  fi
fi
