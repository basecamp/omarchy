(
  if [[ -n $(omarchy-notification-send -u critical -g  "Learn Keybindings" "Super + K for cheatsheet.\nSuper + Space for application launcher.\nSuper + Alt + Space for Omarchy Menu." -a) ]]; then
    omarchy-menu-keybindings
  fi
) >/dev/null 2>&1 &
