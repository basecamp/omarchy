echo "Switch lmstudio -> lmstudio-bin"

if pacman -Q lmstudio &>/dev/null; then
  omarchy-pkg-drop lmstudio
  omarchy-pkg-add lmstudio-bin
fi
