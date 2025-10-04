if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  sudo pacman -S --needed --noconfirm base-devel

  # Configure pacman - use ARM-specific configs on ARM systems
  if [ -n "$OMARCHY_ARM" ]; then
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf.arm /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.arm /etc/pacman.d/mirrorlist
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.asahi-alarm /etc/pacman.d/mirrorlist.asahi-alarm
  else
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist
  fi

  # Refresh all repos
  sudo pacman -Syu --noconfirm
fi
