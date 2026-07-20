notify_update() {
  (
    if [[ -n $(omarchy-notification-send -u critical -g  "Update System" "$1" -a) ]]; then
      omarchy-launch-floating-terminal-with-presentation omarchy-update
    fi
  ) >/dev/null 2>&1 &
}

notify_wifi() {
  (
    if [[ -n $(omarchy-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." -a) ]]; then
      omarchy-shell shell toggle omarchy.network
    fi
  ) >/dev/null 2>&1 &
}

if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then
  notify_update "When you have internet, click to update the system."
  notify_wifi
else
  notify_update "Click to update the system."
fi
