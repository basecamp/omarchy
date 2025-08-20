#!/bin/bash

# Auto-authorize Thunderbolt devices on hotplug
sudo tee /etc/udev/rules.d/99-thunderbolt.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", \
  RUN+="/bin/sh -c 'echo 1 > /sys$devpath/authorized'"
EOF