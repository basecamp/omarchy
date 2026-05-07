if omarchy-battery-present; then
  omarchy_path="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
  run_path="$omarchy_path/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"

  cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --setenv=HOME=$HOME --setenv=OMARCHY_PATH=$omarchy_path --setenv=PATH=$run_path --property=After=power-profiles-daemon.service $omarchy_path/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --setenv=HOME=$HOME --setenv=OMARCHY_PATH=$omarchy_path --setenv=PATH=$run_path --property=After=power-profiles-daemon.service $omarchy_path/bin/omarchy-powerprofiles-set"
EOF

  sudo systemctl enable power-profiles-daemon

  sudo udevadm control --reload 2>/dev/null
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
fi
