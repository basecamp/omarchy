mkdir -p ~/.config/systemd/user/
cp "$OMARCHY_PATH/config/systemd/user/omarchy-sleep-lock.service" ~/.config/systemd/user/
if declare -F omarchy_user_systemctl_enable >/dev/null; then
  omarchy_user_systemctl_enable omarchy-sleep-lock.service
else
  systemctl --user enable omarchy-sleep-lock.service
fi
