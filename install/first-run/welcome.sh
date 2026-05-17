(
  action=$(notify-send -a omarchy-action -u critical --hint=string:omarchy-glyph: "Learn Keybindings" "Super + K for cheatsheet.\nSuper + Space for application launcher.\nSuper + Alt + Space for Omarchy Menu." -A "default=Open")
  [[ $action == "default" ]] && omarchy-menu-keybindings
) >/dev/null 2>&1 &
