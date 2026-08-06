echo "Enable the D-Bus idle-inhibit daemon so apps can suppress the screensaver"

# Enable + start the idle-inhibit daemon for existing Quattro users. It owns
# org.freedesktop.ScreenSaver on the session bus so apps playing video can keep
# the screensaver from firing (issue #6475).
#
# The unit is normally installed by the omarchy-settings package to
# /usr/lib/systemd/user. When the package update and this migration do not land
# together (e.g. a local checkout update), install a user copy so `systemctl
# enable` below can find the unit.
user_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_source="$OMARCHY_PATH/default/systemd/user/omarchy-idle-inhibit.service"
unit_dest="$user_config_home/systemd/user/omarchy-idle-inhibit.service"

if [[ -f $unit_source && ! -f /usr/lib/systemd/user/omarchy-idle-inhibit.service ]]; then
  mkdir -p "$(dirname "$unit_dest")"
  cp "$unit_source" "$unit_dest"
fi

systemctl --user enable --now omarchy-idle-inhibit.service >/dev/null 2>&1 || true
