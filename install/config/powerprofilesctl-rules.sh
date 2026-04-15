if omarchy-battery-present; then
  mapfile -t profiles < <(omarchy-powerprofiles-list)

  if (( ${#profiles[@]} > 1 )); then

    # Default AC profile:
    # 3 profiles → performance
    # 2 profiles → balanced
    ac_profile="${profiles[2]:-${profiles[1]}}"

    # Default Battery profile (balanced)
    battery_profile="${profiles[1]}"

    cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service /usr/bin/powerprofilesctl set $battery_profile"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service /usr/bin/powerprofilesctl set $ac_profile"
EOF

    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=power_supply
  fi
fi
