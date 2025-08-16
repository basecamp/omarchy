#!/bin/bash

# ==============================================================================
# HDMI support fixing for Intel video drivers on Arch Linux
# ==============================================================================
# This script automates the solution to washed HDMI output on Intel drivers.
# This problem is documented here: https://wiki.archlinux.org/title/Intel_graphics#Fix_colors_for_Wayland
#
# Author: https://github.com/CWood-sdf
#
# ==============================================================================

# --- GPU Detection ---
yay -S --noconfirm --needed libdrm

# NOTE: Could possibly do this instead to test for gpu: -n "$(lspci | grep -i 'intel' | grep -i 'vga compatible controller')"
if [ -n "$(/usr/bin/proptest -M i915 -D /dev/dri/card0 | grep -E 'Broadcast|Connector')" ]; then
  # show_logo
  # show_subtext "Fixing Intel driver HDMI support..."

    sudo mkdir -p /usr/local/bin/

  if [ -f /usr/local/bin/intel-wayland-fix-full-color ]; then
    sudo mv /usr/local/bin/intel-wayland-fix-full-color /usr/local/bin/intel-wayland-fix-full-color.backup
  fi
  echo $'#!/bin/bash

readarray -t proptest_result <<<"$(/usr/bin/proptest -M i915 -D /dev/dri/card0 | grep -E \'Broadcast|Connector\')"

for ((i = 0; i < ${#proptest_result[*]}; i += 2)); do
  connector=$(echo ${proptest_result[i]} | awk \'{print $2}\')
  connector_id=$(echo ${proptest_result[i + 1]} | awk \'{print $1}\')

  /usr/bin/proptest -M i915 $connector connector $connector_id 1
done
' | sudo tee /usr/local/bin/intel-wayland-fix-full-color

  sudo chmod +x /usr/local/bin/intel-wayland-fix-full-color


  sudo mkdir -p /etc/udev/rules.d/

  if [ -f /etc/udev/rules.d/80-i915.rules ]; then
    sudo mv /etc/udev/rules.d/80-i915.rules /etc/udev/rules.d/80-i915.rules.backup
  fi

  echo 'ACTION=="add", SUBSYSTEM=="module", KERNEL=="i915", RUN+="/usr/local/bin/intel-wayland-fix-full-color"' | sudo tee /etc/udev/rules.d/80-i915.rules


fi
