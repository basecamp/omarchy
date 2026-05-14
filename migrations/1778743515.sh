echo "Replace mako with the omarchy-shell notification plugin"

# Stop any running instance so the new daemon can take the bus name. The
# unit is Type=dbus / BusName=org.freedesktop.Notifications, so until mako
# releases the name our quickshell server can't register.
pkill -x mako 2>/dev/null || true
systemctl --user stop mako.service 2>/dev/null || true

# Uninstall the package outright. This also deletes
# /usr/lib/systemd/user/mako.service — D-Bus activation has nothing to
# look up once the unit file is gone, so notify-send can never respawn it.
# (`disable` isn't useful here: it only affects boot-time activation, not
#  the on-demand D-Bus path that's how mako actually starts.)
if pacman -Qq mako >/dev/null 2>&1; then
  sudo pacman -Rns --noconfirm mako >/dev/null 2>&1 || true
fi

# Old user config dir is no longer read.
[[ -d ~/.config/mako ]] && rm -rf ~/.config/mako

# Old toggle file is no longer read.
[[ -f ~/.local/state/omarchy/toggles/mako.ini ]] && rm -f ~/.local/state/omarchy/toggles/mako.ini

# Reload the shell so the new NotificationServer claims the bus name.
if command -v omarchy-restart-quickshell >/dev/null 2>&1; then
  omarchy-restart-quickshell >/dev/null 2>&1 || true
fi
