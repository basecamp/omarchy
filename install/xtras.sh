yay -S --noconfirm --needed \
  gnome-calculator gnome-keyring \
  signal-desktop spotify dropbox-cli zoom \
  obsidian-bin typora libreoffice obs-studio kdenlive \
  pinta xournalpp localsend-bin

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-sync-applications || true
