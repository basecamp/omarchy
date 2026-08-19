echo "Enable the Omarchy wallpaper portal backend for this user"

# Ships the backend definition, D-Bus activation entry, and portal config into
# user-level XDG paths so "Set as Background" in Files works without waiting
# for the omarchy-settings package to place the system-wide copies.

portal="$OMARCHY_PATH/default/xdg-desktop-portal/portals/omarchy.portal"
service="$OMARCHY_PATH/default/dbus-1/services/org.freedesktop.impl.portal.desktop.omarchy.service"
config="$OMARCHY_PATH/etc/xdg/xdg-desktop-portal/hyprland-portals.conf"

[[ -f $portal && -f $service && -f $config ]] || exit 0

mkdir -p "$HOME/.local/share/xdg-desktop-portal/portals" "$HOME/.local/share/dbus-1/services" "$HOME/.config/xdg-desktop-portal"
cp "$portal" "$HOME/.local/share/xdg-desktop-portal/portals/"
cp "$service" "$HOME/.local/share/dbus-1/services/"
cp "$config" "$HOME/.config/xdg-desktop-portal/"

# The session bus caches the activation service list, and xdg-desktop-portal
# only reads portal backends and config at startup.
gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig >/dev/null || true
systemctl --user try-restart xdg-desktop-portal.service || true
