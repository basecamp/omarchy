yay -S --noconfirm power-profiles-daemon

if ls /sys/class/power_supply/BAT* &>/dev/null; then
  # This computer runs on a battery, leave powerprofile at Balanced
else
  # Always use maximum power when using a desktop machine
  powerprofilesctl set performance
fi
