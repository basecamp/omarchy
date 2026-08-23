echo "Reload a wedged Wi-Fi radio without waiting for the user"

# first-run only runs once, so existing installs need the unit enabled here.

src="$OMARCHY_PATH/default/systemd/user/omarchy-wifi-recover.service"
sudoers_src="$OMARCHY_PATH/etc/sudoers.d/omarchy-restart-wifi"
sudoers_dest=/etc/sudoers.d/omarchy-restart-wifi
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

# The watcher is in the omarchy package; the grant lives in omarchy-settings.
# During package skew the unit can be enabled with no sudoers file, and
# every reload fails silently. Install the drop-in ourselves when missing.
if [[ ! -f $sudoers_dest && -f $sudoers_src ]]; then
  if visudo -cf "$sudoers_src" >/dev/null 2>&1; then
    sudo install -Dm440 "$sudoers_src" "$sudoers_dest"
  fi
fi

if [[ -f /usr/lib/systemd/user/omarchy-wifi-recover.service ]]; then
  rm -f "$config_home/systemd/user/omarchy-wifi-recover.service"
elif [[ -f $src ]]; then
  install -Dm644 "$src" "$config_home/systemd/user/omarchy-wifi-recover.service"
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY does
# not have, so fall back to writing the symlink it would have written.
if ! systemctl --user enable omarchy-wifi-recover.service >/dev/null 2>&1; then
  wants_dir="$config_home/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  if [[ -f /usr/lib/systemd/user/omarchy-wifi-recover.service ]]; then
    ln -sfn /usr/lib/systemd/user/omarchy-wifi-recover.service \
      "$wants_dir/omarchy-wifi-recover.service"
  elif [[ -f $config_home/systemd/user/omarchy-wifi-recover.service ]]; then
    ln -sfn ../omarchy-wifi-recover.service \
      "$wants_dir/omarchy-wifi-recover.service"
  fi
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-wifi-recover.service >/dev/null 2>&1 || true
fi
