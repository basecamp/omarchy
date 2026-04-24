#!/bin/bash

# Fix auto power profile switching on USB-C only machines
# See: https://github.com/basecamp/omarchy/issues/5412

echo "Fixing power profile switching for USB-C machines..."

# Check if we're on a USB-C only machine
HAS_MAINS=$(cat /sys/class/power_supply/AC/type 2>/dev/null | grep -c "Mains" || echo 0)
HAS_USB=$(ls /sys/class/power_supply/*/type 2>/dev/null | xargs grep -l "USB" 2>/dev/null | head -1)

if [[ "$HAS_MAINS" -eq 0 && -n "$HAS_USB" ]]; then
  echo "USB-C only machine detected, adding USB power supply udev rules..."
fi

# Update the udev rules for power profile switching
cat << 'EOF' | sudo tee "/etc/udev/rules.d/99-power-profile.rules" > /dev/null
# Power profile switching for traditional AC (Mains) power supplies
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set battery"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set ac"

# Power profile switching for USB-C Power Delivery
SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_TYPE}=="USB", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set battery"
SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_TYPE}=="USB", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set ac"

# Additional support for USB-C Power Source devices
SUBSYSTEM=="power_supply", ATTR{type}=="USB", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set battery"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set ac"
EOF

# Ensure power-profiles-daemon is enabled
sudo systemctl enable power-profiles-daemon 2>/dev/null || true

# Reload udev rules and trigger power supply events
sudo udevadm control --reload 2>/dev/null
sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null

notify-send "Power profile fix applied" "USB-C power profile switching enabled. Restart if not working."
