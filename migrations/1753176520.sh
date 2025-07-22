echo "Install wf-recorder for screen recording for nvidia"

if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  if ! command -v wf-recorder &>/dev/null; then
    yay -S --noconfirm --needed wf-recorder
  fi

  if command -v wl-screenrec &>/dev/null; then
    yay -R --noconfirm wl-screenrec
  fi
fi
