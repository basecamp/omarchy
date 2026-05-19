notify_update() {
  (
    action=$(notify-send -a omarchy-action -u critical --hint=string:omarchy-glyph: "Update System" "$1" -A "default=Update")
    [[ $action == "default" ]] && omarchy-launch-floating-terminal-with-presentation omarchy-update
  ) >/dev/null 2>&1 &
}

notify_wifi() {
  (
    action=$(notify-send -a omarchy-action -u critical --hint=string:omarchy-glyph:󰖩 "Click to Setup Wi-Fi" -A "default=Setup")
    [[ $action == "default" ]] && omarchy-shell networkPanel toggle
  ) >/dev/null 2>&1 &
}

if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then
  notify_update "When you have internet, click to update the system."
  notify_wifi
else
  notify_update "Click to update the system."
fi
