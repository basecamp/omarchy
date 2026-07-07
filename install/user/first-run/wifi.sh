state_dir="$HOME/.local/state/omarchy"
skip_update_notification_file="$state_dir/skip-first-run-update-notification"
skip_update_notification=0
if [[ -f $skip_update_notification_file ]]; then
  skip_update_notification=1
  rm -f "$skip_update_notification_file"
fi

notify_update() {
  (( skip_update_notification )) && return 0

  (
    if [[ -n $(omarchy-notification-send -u critical -g  "Update System" "$1" -a) ]]; then
      omarchy-launch-floating-terminal-with-presentation omarchy-update
    fi
  ) >/dev/null 2>&1 &
}

notify_wifi() {
  (
    if [[ -n $(omarchy-notification-send -u critical -g 󰖩 "Click to Setup Wi-Fi" -a) ]]; then
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
