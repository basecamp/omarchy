mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" ~/.config/wireplumber/wireplumber.conf.d/

# Quickshell.Bluetooth has no Agent API, so the omarchy.bluetooth plugin
# can't answer the auth prompts bluez issues during pair(). bt-agent registers
# a NoInputNoOutput agent on the system bus so pair() actually completes.
mkdir -p ~/.config/systemd/user/
cp "$OMARCHY_PATH/config/systemd/user/bt-agent.service" ~/.config/systemd/user/
if declare -F omarchy_user_systemctl_enable >/dev/null; then
  omarchy_user_systemctl_enable bt-agent.service
else
  systemctl --user enable bt-agent.service
fi
