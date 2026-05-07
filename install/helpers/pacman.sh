use_omarchy_pacman_config() {
  local mirror="${OMARCHY_MIRROR:-stable}"
  local archzfs_repo

  archzfs_repo=$(mktemp)

  if [[ -f /etc/pacman.conf ]]; then
    awk '
      /^\[/ { in_archzfs = ($0 == "[archzfs]") }
      in_archzfs { print }
    ' /etc/pacman.conf >"$archzfs_repo"
  fi

  sudo cp -f "$OMARCHY_PATH/default/pacman/pacman-$mirror.conf" /etc/pacman.conf
  sudo cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-$mirror" /etc/pacman.d/mirrorlist

  if [[ -s $archzfs_repo ]]; then
    printf "\n" | sudo tee -a /etc/pacman.conf >/dev/null
    sudo tee -a /etc/pacman.conf <"$archzfs_repo" >/dev/null
  fi

  rm -f "$archzfs_repo"
}

export -f use_omarchy_pacman_config
