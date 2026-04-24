#!/bin/bash

# Udev rules for automatic power profile switching based on AC/battery state.
# Handles both traditional Mains power supplies and USB-C power delivery.

echo "Installing power profile udev rules..."

# Get absolute path for the script
OMARCHY_SCRIPT="$(realpath "$HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set" 2>/dev/null || echo "$HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set")"

# Create udev rules for power profile switching
cat << RULESEOF > /tmp/99-power-profile.rules
# Power profile switching for traditional AC (Mains) power supplies
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service $OMARCHY_SCRIPT battery"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service $OMARCHY_SCRIPT ac"

# Power profile switching for USB-C Power Delivery
# Many modern laptops (ThinkPads, MacBooks, ultrabooks) use USB-C for charging
SUBSYSTEM=="power_supply", ATTR{type}=="USB", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service $OMARCHY_SCRIPT battery"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service $OMARCHY_SCRIPT ac"
RULESEOF

sudo mv /tmp/99-power-profile.rules /etc/udev/rules.d/99-power-profile.rules

# Reload udev rules and trigger power supply events
sudo udevadm control --reload 2>/dev/null
sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null

echo "Power profile udev rules installed successfully!"
