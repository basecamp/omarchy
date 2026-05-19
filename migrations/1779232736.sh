echo "Install bluetooth pairing agent for the shell bluetoothPanel"

# Hold bluez explicit so a future cascade-remove (e.g. uninstalling a TUI
# that listed it as a dep) doesn't take it down with it. Idempotent if it
# already is.
omarchy-cmd-present pacman && sudo pacman -D --asexplicit bluez >/dev/null 2>&1 || true

# Quickshell.Bluetooth exposes pair()/trust()/connect() but no Agent surface,
# so the bluetoothPanel can't answer the auth prompts bluez issues during
# pair(). Without an org.bluez.Agent1 registered, pair() stalls at the
# confirmation step and the device ends up half-paired (Paired:no,
# Trusted:yes), then connect attempts fail with br-connection-key-missing.
# bluez-tools' bt-agent fills that gap; bluez-utils provides bluetoothctl
# for manual recovery.
omarchy-pkg-add bluez-utils bluez-tools

mkdir -p ~/.config/systemd/user/
cp "$OMARCHY_PATH/config/systemd/user/bt-agent.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-agent.service
