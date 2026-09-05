echo "Move the XDG Desktop target out of the home directory"

if [[ $(xdg-user-dir DESKTOP) == "$HOME" ]]; then
  mkdir -p "$HOME/.local/share/desktop"
  xdg-user-dirs-update --set DESKTOP "$HOME/.local/share/desktop"
fi
