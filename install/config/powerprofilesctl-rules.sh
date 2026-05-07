if omarchy-battery-present; then
  user_uid=$(id -u)
  omarchy_path="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
  run_path="$omarchy_path/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"
  run_command="/usr/bin/runuser -u $USER -- /usr/bin/env HOME=$HOME OMARCHY_PATH=$omarchy_path XDG_RUNTIME_DIR=/run/user/$user_uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_uid/bus PATH=$run_path /usr/bin/systemd-run --user --quiet --collect $omarchy_path/bin/omarchy-powerprofiles-set"

  cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="$run_command"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="$run_command"
EOF

  sudo systemctl enable power-profiles-daemon

  sudo udevadm control --reload 2>/dev/null
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
fi
