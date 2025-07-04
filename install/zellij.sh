if ! command -v zellij &>/dev/null; then
  yay -S --noconfirm --needed zellij

  rm -rf ~/.config/zellij
  mkdir -p ~/.config/zellij
  cp -R ~/.local/share/omarchy/config/zellij/* ~/.config/zellij/
fi
