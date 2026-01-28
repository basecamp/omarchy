battery_present() {
  for bat in /sys/class/power_supply/BAT*; do
    [[ -r "$bat/present" ]] &&
    [[ "$(cat "$bat/present")" == "1" ]] &&
    [[ "$(cat "$bat/type")" == "Battery" ]] &&
    return 0
  done
  return 1
}

if battery_present; then
  sudo mkdir -p /etc/udev/rules.d

  cat <<'EOF' | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set power-saver"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set balanced"
EOF
  sudo udevadm control --reload
fi
