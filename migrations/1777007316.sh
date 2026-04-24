#!/bin/bash

# Fix screen sharing notification bar "Hide" button not responding
# See: https://github.com/basecamp/omarchy/issues/5373

echo "Adding screen sharing notification bar fixes"

# Add screen-sharing.conf to the app configs if it doesn't exist
SCREEN_SHARING_CONF="$HOME/.config/hypr/apps/screen-sharing.conf"
if [[ ! -f $SCREEN_SHARING_CONF ]]; then
  cat > "$SCREEN_SHARING_CONF" << 'CONFEOF'
# Screen sharing notification bar fixes
# Fix for: Screen sharing notification bar "Hide" button not responding to clicks
# The notification bar from Chromium/Chrome needs to be on a layer that receives input

# Ensure notification popups from browsers receive input
windowrule = float, class:^(chrome|chromium|brave|microsoft-edge),title:.*(screen sharing|Sharing|is sharing|Stop sharing|Hide)
windowrule = noborder, class:^(chrome|chromium|brave|microsoft-edge),title:.*(screen sharing|Sharing|is sharing|Stop sharing|Hide)
windowrule = noblur, class:^(chrome|chromium|brave|microsoft-edge),title:.*(screen sharing|Sharing|is sharing|Stop sharing|Hide)
CONFEOF
  notify-send "Screen sharing fix applied" "Restart Hyprland to apply changes"
fi
