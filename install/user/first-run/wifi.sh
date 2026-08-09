notify_update() {
  omarchy-notification-send -u critical -g  "Update System" "$1" \
    --exec "omarchy-launch-floating-terminal-with-presentation omarchy-update"
}

notify_wifi() {
  omarchy-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." \
    --exec "omarchy-shell shell toggle omarchy.network"
}

if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then
  # Newest stacks on top, and Wi-Fi is what you need first, so send it last.
  notify_update "When you have internet, click to update the system."
  notify_wifi
else
  notify_update "Click to update the system."
fi
