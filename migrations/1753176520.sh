echo "Install wf-recorder for screen recording for nvidia"

if lspci | grep -qi 'nvidia'; then
  if ! command -v wf-recorder &>/dev/null; then
    sudo pacman -S --noconfirm --needed wf-recorder
  fi

  if command -v wl-screenrec &>/dev/null; then
    yay -R --noconfirm wl-screenrec
  fi
fi
