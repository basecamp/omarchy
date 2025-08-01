echo "Add icon theme coloring"

if ! yay -! yaru-icon-theme &>/dev/null; then
  yay -S --noconfirm yaru-icon-theme

  if [[ -f ~/.config/omarchy/current/theme/icons.theme ]]; then
    gsettings set org.gnome.desktop.interface icon-theme "$(<~/.config/omarchy/current/theme/icons.theme)"
  fi
fi
