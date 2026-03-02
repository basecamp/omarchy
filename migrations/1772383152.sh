echo "Enable power saver profile on low battery for laptops"

if omarchy-battery-present && [[ ! -f ~/.config/systemd/user/omarchy-powerprofile-low-battery.service ]]; then
  mkdir -p ~/.config/systemd/user

  cp $OMARCHY_PATH/config/systemd/user/omarchy-powerprofile-low-battery.* ~/.config/systemd/user/

  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-powerprofile-low-battery.timer || true
fi
