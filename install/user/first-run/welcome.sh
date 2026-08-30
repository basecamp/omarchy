# Real newlines, not a literal \n: the card renders the body as it arrives, and
# elides past three lines.
omarchy-notification-send -u critical -g  "Learn Keybindings" \
  $'Super + K for keybindings, in Omarchy or any app.\nSuper + Space for Omarchy Menu.' \
  --exec omarchy-menu-keybindings
