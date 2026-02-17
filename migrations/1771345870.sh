if pacman -Q lmstudio &>/dev/null; then
  echo "Switch lmstudio -> lmstudio-bin"

  omarchy-pkg-drop lmstudio
  omarchy-pkg-add lmstudio-bin
fi

