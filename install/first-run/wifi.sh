if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then
  notify-send "󰖩    Click to Setup Wi-Fi" "Tab between sections, space selects, ? for help." -u critical -t 30000
fi
