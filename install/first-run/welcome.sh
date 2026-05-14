(
  action=$(notify-send "    Learn Keybindings" "Super + K for cheatsheet.\nSuper + Space for application launcher.\nSuper + Alt + Space for Omarchy Menu." -u critical -A "default=Open")
  [[ $action == "default" ]] && omarchy-menu-keybindings
) >/dev/null 2>&1 &
