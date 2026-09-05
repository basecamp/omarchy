# Mirror keyboard backlight onto the ROG Flow Z13 2025 chassis window LED.
# Fn+F11 is consumed by hid-asus, so a waiter on brightness_hw_changed is the
# only userspace edge. Non-GZ302 machines must not enable this unit.

if omarchy-hw-asus-rog && omarchy-hw-match "GZ302"; then
  # omarchy-settings does not install this unit under /usr/lib yet. The user
  # copy is loadable from the checkout without that package change.
  mkdir -p "$HOME/.config/systemd/user"
  cp "$OMARCHY_PATH/default/systemd/user/omarchy-brightness-keyboard-watch.service" \
    "$HOME/.config/systemd/user/omarchy-brightness-keyboard-watch.service"

  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if ! systemctl --user enable omarchy-brightness-keyboard-watch.service >/dev/null 2>&1; then
    wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
    mkdir -p "$wants_dir"
    ln -sfn "$HOME/.config/systemd/user/omarchy-brightness-keyboard-watch.service" \
      "$wants_dir/omarchy-brightness-keyboard-watch.service"
  fi

  if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start omarchy-brightness-keyboard-watch.service >/dev/null 2>&1 || true
  fi
fi
