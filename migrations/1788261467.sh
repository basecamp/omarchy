echo "Expose GNOME Keyring to sandboxed apps through the Secret portal"

portal_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal"
portal_config="$portal_dir/hyprland-portals.conf"
generic_config="$portal_dir/portals.conf"

# Only apply if not configured yet
if [[ -e $portal_config || -L $portal_config ]]; then
  echo "Portal already configured, skipping..."
  exit 0
elif [[ -e $generic_config || -L $generic_config ]]; then
  echo "Portal already configured, skipping..."
  exit 0
fi

install -Dm644 "$OMARCHY_PATH/config/xdg-desktop-portal/hyprland-portals.conf" "$portal_config"

# Activate the backend immediately in a live desktop
if systemctl --user is-active --quiet xdg-desktop-portal.service 2>/dev/null; then
  if ! systemctl --user restart xdg-desktop-portal.service; then
    echo "Failed to restart xdg-desktop-portal" >&2
  fi
fi
