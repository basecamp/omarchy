echo "Sync ThinkBook hardware mute LEDs with WirePlumber state"

# Install udev rule so users in the video group can write to the platform mute LED nodes.
# On ThinkBook laptops, the kernel exposes platform::mute and platform::micmute
# under /sys/class/leds/ with root-only write permissions by default.
if omarchy-hw-match "ThinkBook"; then
  sudo tee /etc/udev/rules.d/99-lenovo-thinkbook-leds.rules > /dev/null << 'EOF'
# Allow users in the video group to control ThinkBook platform mute LEDs
SUBSYSTEM=="leds", KERNEL=="platform::mute",    ACTION=="add|change", RUN+="/usr/bin/chgrp video /sys%p/brightness", RUN+="/usr/bin/chmod 0664 /sys%p/brightness"
SUBSYSTEM=="leds", KERNEL=="platform::micmute", ACTION=="add|change", RUN+="/usr/bin/chgrp video /sys%p/brightness", RUN+="/usr/bin/chmod 0664 /sys%p/brightness"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=leds
fi
