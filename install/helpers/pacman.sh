use_omarchy_pacman_config() {
  local mirror="${OMARCHY_MIRROR:-stable}"
  local archzfs_repo=""

  if [[ -f /etc/pacman.conf ]]; then
    archzfs_repo=$(awk '
      /^\[/ { in_archzfs = ($0 == "[archzfs]") }
      in_archzfs { print }
    ' /etc/pacman.conf)
  fi

  sudo cp -f "$OMARCHY_PATH/default/pacman/pacman-$mirror.conf" /etc/pacman.conf
  sudo cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-$mirror" /etc/pacman.d/mirrorlist

  if [[ -n $archzfs_repo ]]; then
    printf "\n" | sudo tee -a /etc/pacman.conf >/dev/null
    printf "%s\n" "$archzfs_repo" | sudo tee -a /etc/pacman.conf >/dev/null
  fi
}

export -f use_omarchy_pacman_config
