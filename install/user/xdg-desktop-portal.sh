portal_config="$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
nautilus_portal="$HOME/.local/share/xdg-desktop-portal/portals/nautilus.portal"

mkdir -p "$(dirname "$portal_config")" "$(dirname "$nautilus_portal")"

if [[ ! -e $portal_config ]]; then
  printf '%s\n' \
    '[preferred]' \
    'default=hyprland;gtk' \
    'org.freedesktop.impl.portal.FileChooser=nautilus' >"$portal_config"
elif ! grep -q '^org\.freedesktop\.impl\.portal\.FileChooser=' "$portal_config"; then
  if grep -q '^\[preferred\]$' "$portal_config"; then
    sed -i '/^\[preferred\]$/a org.freedesktop.impl.portal.FileChooser=nautilus' "$portal_config"
  else
    sed -i '1i [preferred]\norg.freedesktop.impl.portal.FileChooser=nautilus\n' "$portal_config"
  fi
fi

printf '%s\n' \
  '[portal]' \
  'DBusName=org.gnome.Nautilus' \
  'Interfaces=org.freedesktop.impl.portal.FileChooser' \
  'UseIn=Hyprland' >"$nautilus_portal"
