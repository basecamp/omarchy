# Grant users in the video group write access to the ThinkBook platform mute LEDs.
# Without this, only root can update platform::mute and platform::micmute,
# so keybinding scripts cannot sync the hardware LED to WirePlumber state.

if omarchy-hw-match "ThinkBook"; then
  sudo tee /etc/udev/rules.d/99-lenovo-thinkbook-leds.rules << 'EOF'
# Allow users in the video group to control ThinkBook platform mute LEDs
SUBSYSTEM=="leds", KERNEL=="platform::mute",    ACTION=="add|change", RUN+="/usr/bin/chgrp video /sys%p/brightness", RUN+="/usr/bin/chmod 0664 /sys%p/brightness"
SUBSYSTEM=="leds", KERNEL=="platform::micmute", ACTION=="add|change", RUN+="/usr/bin/chgrp video /sys%p/brightness", RUN+="/usr/bin/chmod 0664 /sys%p/brightness"
EOF

  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=leds
fi
