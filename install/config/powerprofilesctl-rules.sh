if omarchy-battery-present; then
  mapfile -t profiles < <(omarchy-powerprofiles-list)

  if [[ ${#profiles[@]} -gt 0 ]]; then

    # Default AC profile:
    # 3 profiles → performance
    # 2 profiles → balanced
    # 1 profile  → profiles[0]
    ac_profile="${profiles[2]:-${profiles[1]:-${profiles[0]}}}"

    # Default Battery profile:
    # 3 profiles → balanced
    # 2 profiles → balanced
    # 1 profile  → profiles[0]
    battery_profile="${profiles[1]:-${profiles[0]}}"

    cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set $battery_profile"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set $ac_profile"
EOF

    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=power_supply
  fi
fi
