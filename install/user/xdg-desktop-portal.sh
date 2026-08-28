config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

portal_config="$config_home/xdg-desktop-portal/hyprland-portals.conf"
# portals.conf is read from $XDG_CONFIG_HOME. .portal descriptors are not:
# xdg-desktop-portal (>= 1.21.0) loads them from $XDG_DATA_HOME, then
# $XDG_DATA_DIRS, then /usr/share. A file under
# ~/.config/xdg-desktop-portal/portals/ is ignored.
nautilus_portal="$data_home/xdg-desktop-portal/portals/nautilus.portal"
nautilus_dbus_service="$data_home/dbus-1/services/org.gnome.Nautilus.service"

mkdir -p \
  "$(dirname "$portal_config")" \
  "$(dirname "$nautilus_portal")" \
  "$(dirname "$nautilus_dbus_service")"

if [[ ! -e $portal_config ]]; then
  printf '%s\n' \
    '[preferred]' \
    'default=hyprland;gtk' \
    'org.freedesktop.impl.portal.FileChooser=nautilus' >"$portal_config"
elif ! grep -q '^org\.freedesktop\.impl\.portal\.FileChooser=' "$portal_config"; then
  # Tolerate surrounding whitespace on the section header: a miss here falls
  # through to inserting a second [preferred], and GKeyFile treats a duplicate
  # group as a parse error, which would take out portals.conf loading entirely.
  if grep -qE '^[[:space:]]*\[preferred\][[:space:]]*$' "$portal_config"; then
    sed -i -E '/^[[:space:]]*\[preferred\][[:space:]]*$/a org.freedesktop.impl.portal.FileChooser=nautilus' "$portal_config"
  else
    sed -i '1i [preferred]\norg.freedesktop.impl.portal.FileChooser=nautilus\n' "$portal_config"
  fi
fi

# No UseIn key: that is the deprecated pre-portals.conf selector, consulted only
# when portals.conf picks nothing, and xdg-desktop-portal logs a deprecation
# warning when it falls back to it.
printf '%s\n' \
  '[portal]' \
  'DBusName=org.gnome.Nautilus' \
  'Interfaces=org.freedesktop.impl.portal.FileChooser' >"$nautilus_portal"

# Deadlock guard. Registering a GTK4/libadwaita app as a portal backend makes
# xdg-desktop-portal activate it from inside its own init to build the
# FileChooser impl proxy; Nautilus's startup then calls synchronously back into
# the still-activating portal. Only the 25s D-Bus timeout breaks the cycle, and
# every GTK app in the session queues behind the pending activation. There are
# two independent synchronous callers, one per toolkit layer, each with its own
# opt-out: GDK's startup portal query (GDK_DEBUG=no-portals) and libadwaita's
# AdwSettingsImplPortal constructor (ADW_DISABLE_PORTAL=1, falls back to its
# GSettings impl). Disarming only one moves the stall up a layer rather than
# fixing it. Nautilus needs neither: it is the chooser, and theming still
# tracks GSettings.
printf '%s\n' \
  '[D-BUS Service]' \
  'Name=org.gnome.Nautilus' \
  'Exec=/usr/bin/env GDK_DEBUG=no-portals ADW_DISABLE_PORTAL=1 /usr/bin/nautilus --gapplication-service' >"$nautilus_dbus_service"
