echo "Install dynamic background config and systemd units"

if [[ ! -f $HOME/.config/omarchy/dynamic-bg/dynamic-bg.conf ]]; then
  mkdir -p "$HOME/.config/omarchy/dynamic-bg"
  cp "$OMARCHY_PATH/config/omarchy/dynamic-bg/dynamic-bg.conf" "$HOME/.config/omarchy/dynamic-bg/dynamic-bg.conf"
fi

mkdir -p "$HOME/.config/systemd/user"

for unit in omarchy-dynamic-bg.service omarchy-dynamic-bg.timer; do
  if [[ ! -f $HOME/.config/systemd/user/$unit ]]; then
    cp "$OMARCHY_PATH/config/systemd/user/$unit" "$HOME/.config/systemd/user/$unit"
  fi
done

systemctl --user daemon-reload
