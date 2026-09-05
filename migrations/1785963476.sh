echo "Enable the D-Bus idle-inhibit daemon so apps can suppress the screensaver"

# Enable + start the idle-inhibit daemon for existing Quattro users. It owns
# org.freedesktop.ScreenSaver on the session bus so apps playing video can keep
# the screensaver from firing (issue #6475).

# The daemon imports python-dbus. `omarchy update` runs `pacman -Syu`, which does
# not reconcile install/omarchy-base.packages, so existing users may not have the
# dependency yet; install it before starting the service.
if omarchy-pkg-missing python-dbus; then
  omarchy-pkg-add python-dbus
fi

# The unit is normally installed by the omarchy-settings package to
# /usr/lib/systemd/user. When the package update and this migration do not land
# together (e.g. a local checkout update), link a user copy so systemctl and the
# wants symlink below can find the unit. Symlink, not copy: a copied unit at
# ~/.config/systemd/user would permanently shadow the packaged unit and never
# receive later fixes, while the link tracks the checkout it came from.
user_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_source="$OMARCHY_PATH/default/systemd/user/omarchy-idle-inhibit.service"
unit_dest="$user_config_home/systemd/user/omarchy-idle-inhibit.service"
unit_target="/usr/lib/systemd/user/omarchy-idle-inhibit.service"

# Resolve which file systemctl should load: the packaged unit when it exists,
# otherwise the checkout link. Prefer the packaged path so the wants symlink
# keeps tracking package fixes rather than a user-dir copy.
if [[ ! -f $unit_target ]]; then
  unit_target="$unit_dest"
  if [[ -f $unit_source ]]; then
    mkdir -p "$(dirname "$unit_dest")"
    ln -sfn "$unit_source" "$unit_dest"
  fi
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY/SSH
# does not have. Fall back to writing exactly the symlink it would have written,
# rather than silently leaving the daemon unenabled and the migration marked
# complete (which would strand the unit at the next graphical login).
if ! systemctl --user enable omarchy-idle-inhibit.service >/dev/null 2>&1; then
  wants_dir="$user_config_home/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn "$unit_target" "$wants_dir/omarchy-idle-inhibit.service"
fi

# Outside a graphical session there is no shell to feed idle inhibitors to; the
# enablement above is the whole job, and the next graphical login starts it.
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-idle-inhibit.service >/dev/null 2>&1 || true
fi
