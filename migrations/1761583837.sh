echo "Ensure nvim started from app launcher always starts nvim not $EDITOR"

if [ -f /usr/share/applications/nvim.desktop ]; then
  rm ~/.local/share/applications/nvim.desktop
  ln -s /usr/share/applications/nvim.desktop ~/.local/share/applications/nvim.desktop
  update-desktop-database ~/.local/share/applications
fi
