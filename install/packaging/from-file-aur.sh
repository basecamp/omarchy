if [[ $# -lt 1 ]]; then
  echo "Must specify file to install from!"
  exit
fi

if [[ -f "$OMARCHY_INSTALL/$1" ]]; then
  # Fetch all in file
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/$1" | grep -v '^$')
  if [[ ${#packages[@]} -ne 0 ]]; then
    # Install all of them
    yay -Sua --noconfirm "${packages[@]}"
  fi
fi
