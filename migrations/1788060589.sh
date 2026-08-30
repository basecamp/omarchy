echo "Move system sleep hooks into package ownership"

known_unowned_file() {
  local path=$1
  local current_sha256 known_sha256 report status
  shift

  # Do not follow a symlink or read from a device/FIFO at a legacy path.
  if [[ ! -f $path || -L $path ]]; then
    return 1
  fi

  if report=$(LC_ALL=C pacman -Qo "$path" 2>&1); then
    return 1
  else
    status=$?
  fi
  if (( status != 1 )) || [[ $report != "error: No package owns $path" ]]; then
    echo "Unable to verify package ownership for $path: $report" >&2
    return 2
  fi

  if ! current_sha256=$(sudo sha256sum -- "$path" | awk '{ print $1 }'); then
    echo "Unable to hash legacy path $path" >&2
    return 2
  fi
  for known_sha256; do
    if [[ $current_sha256 == "$known_sha256" ]]; then
      return 0
    fi
  done
  return 1
}

legacy_keyboard=/usr/lib/systemd/system-sleep/keyboard-backlight
packaged_keyboard=/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight
if known_unowned_file "$legacy_keyboard" f313a81e47401f0d38b8602e5997f52c5286d5e97f74027564ddd515b3d16511; then
  if [[ ! -x $packaged_keyboard ]]; then
    echo "$packaged_keyboard is missing; update omarchy-settings before retrying this migration." >&2
    exit 1
  fi
  sudo rm -f -- "$legacy_keyboard"
else
  legacy_status=$?
  if (( legacy_status == 2 )); then
    exit "$legacy_status"
  fi
fi

legacy_force_igpu=/usr/lib/systemd/system-sleep/force-igpu
packaged_force_igpu=/usr/lib/systemd/system-sleep/omarchy-force-igpu
legacy_delay=/etc/systemd/system/supergfxd.service.d/delay-start.conf
packaged_delay=/usr/share/omarchy/default/systemd/system/supergfxd.service.d/delay-start.conf
force_igpu_marker=/etc/omarchy/force-igpu
delay_link=/etc/systemd/system/supergfxd.service.d/10-omarchy-delay-start.conf

if known_unowned_file \
  "$legacy_force_igpu" \
  d604e7c4903829563e45fc52188fc5602c3f1bc66e247f0a2cc0a974ed6e57db \
  de620729f0c824225487ab988a53158de7336e4151d594c49641a99ed5740e6b; then
  if [[ ! -x $packaged_force_igpu ]]; then
    echo "$packaged_force_igpu is missing; update omarchy-settings before retrying this migration." >&2
    exit 1
  fi

  marker_ready=0
  if [[ -f $force_igpu_marker && ! -L $force_igpu_marker ]]; then
    marker_ready=1
  elif [[ ! -e $force_igpu_marker && ! -L $force_igpu_marker ]]; then
    sudo install -d -m 0755 /etc/omarchy
    sudo install -m 0644 /dev/null "$force_igpu_marker"
    marker_ready=1
  fi

  if (( marker_ready )); then
    sudo rm -f -- "$legacy_force_igpu"
  else
    echo "Preserving $legacy_force_igpu because $force_igpu_marker contains administrator state." >&2
  fi
else
  legacy_status=$?
  if (( legacy_status == 2 )); then
    exit "$legacy_status"
  fi
fi

if known_unowned_file "$legacy_delay" 29e4646cf5dcbeacd12eb82e8beac3a9aa61a44ec43c3c91be9e1f3005065c61; then
  if [[ ! -f $packaged_delay ]]; then
    echo "$packaged_delay is missing; update omarchy-settings before retrying this migration." >&2
    exit 1
  fi

  delay_ready=0
  if [[ -L $delay_link && $(readlink "$delay_link") == "$packaged_delay" ]]; then
    delay_ready=1
  elif [[ ! -e $delay_link && ! -L $delay_link ]]; then
    sudo install -d -m 0755 /etc/systemd/system/supergfxd.service.d
    sudo ln -s "$packaged_delay" "$delay_link"
    delay_ready=1
  fi

  if (( delay_ready )); then
    sudo rm -f -- "$legacy_delay"
  else
    echo "Preserving $legacy_delay because $delay_link contains administrator state." >&2
  fi
else
  legacy_status=$?
  if (( legacy_status == 2 )); then
    exit "$legacy_status"
  fi
fi
