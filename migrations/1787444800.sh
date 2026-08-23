echo "Reload a wedged Wi-Fi radio without waiting for the user"

# first-run only runs once, so existing installs need the unit enabled here.

src="$OMARCHY_PATH/default/systemd/user/omarchy-wifi-recover.service"
sudoers_src="$OMARCHY_PATH/etc/sudoers.d/omarchy-restart-wifi"
# Overridable only so the test can exercise both halves of every branch here;
# the watcher already reads its packaged unit the same way.
sudoers_dest=${OMARCHY_WIFI_SUDOERS_DEST:-/etc/sudoers.d/omarchy-restart-wifi}
packaged_unit=${OMARCHY_WIFI_RECOVER_PACKAGED_UNIT:-/usr/lib/systemd/user/omarchy-wifi-recover.service}
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

# The watcher is in the omarchy package; the grant lives in omarchy-settings.
# During package skew the unit can be enabled with no sudoers file, and
# every reload fails silently. Install the drop-in ourselves when missing.
#
# Nothing here may abort: migrations run under `bash -euo pipefail`, so a
# cancelled password prompt or a user outside %wheel would take out every
# migration queued behind this one. Say what went wrong and carry on.
if [[ ! -f $sudoers_dest && -f $sudoers_src ]]; then
  if ! visudo -cf "$sudoers_src" >/dev/null 2>&1; then
    echo "  Skipping the Wi-Fi sudoers grant: $sudoers_src does not parse"
  elif ! sudo install -Dm440 "$sudoers_src" "$sudoers_dest"; then
    echo "  Could not install $sudoers_dest; automatic Wi-Fi recovery stays off until omarchy-settings ships it"
  fi
fi

staged="$config_home/systemd/user/omarchy-wifi-recover.service"
if [[ -f $packaged_unit ]]; then
  # Only when it is still stock. An edited copy is the user's, and a copy
  # matching either shipped version is one of ours to clean up.
  if [[ -f $staged ]] &&
    { cmp -s "$staged" "$packaged_unit" ||
      { [[ -f $src ]] && cmp -s "$staged" "$src"; }; }; then
    rm -f "$staged"
  fi
elif [[ -f $src && ! -f $staged ]]; then
  install -Dm644 "$src" "$staged"
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY does
# not have, so fall back to writing the symlink it would have written.
if ! systemctl --user enable omarchy-wifi-recover.service >/dev/null 2>&1; then
  wants_dir="$config_home/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  if [[ -f $packaged_unit ]]; then
    ln -sfn "$packaged_unit" \
      "$wants_dir/omarchy-wifi-recover.service"
  elif [[ -f $config_home/systemd/user/omarchy-wifi-recover.service ]]; then
    ln -sfn ../omarchy-wifi-recover.service \
      "$wants_dir/omarchy-wifi-recover.service"
  fi
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-wifi-recover.service >/dev/null 2>&1 || true
fi
