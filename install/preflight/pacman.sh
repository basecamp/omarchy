if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  sudo pacman -S --needed --noconfirm base-devel

  # Configure pacman
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
  
  # Support for China mirrors - users can set OMARCHY_USE_CHINA_MIRRORS=1
  if [[ "${OMARCHY_USE_CHINA_MIRRORS:-0}" == "1" ]]; then
    echo "Using China mirrors for better connectivity in mainland China..."
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-china /etc/pacman.d/mirrorlist
  else
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-stable /etc/pacman.d/mirrorlist
  fi

  # Try multiple keyservers for better reliability, especially in China
  KEYSERVERS=(
    "keys.openpgp.org"
    "keyserver.ubuntu.com"
    "pgp.mit.edu"
    "keyserver.pgp.com"
  )
  
  KEY_RECEIVED=false
  for keyserver in "${KEYSERVERS[@]}"; do
    echo "Attempting to receive key from $keyserver..."
    if sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver "$keyserver" 2>/dev/null; then
      KEY_RECEIVED=true
      echo "Successfully received key from $keyserver"
      break
    fi
  done
  
  if [ "$KEY_RECEIVED" = false ]; then
    echo "Warning: Failed to receive key from all keyservers. Installation may fail."
    echo "You may need to manually import the key or check your network connection."
  else
    # Only sign the key if it was successfully received
    sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
  fi

  sudo pacman -Sy
  sudo pacman -S --noconfirm --needed omarchy-keyring


  # Refresh all repos
  sudo pacman -Syu --noconfirm
fi
