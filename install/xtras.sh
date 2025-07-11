if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed \
    gnome-calculator \
    signal-desktop spotify dropbox-cli zoom \
    obsidian-bin typora libreoffice obs-studio kdenlive \
    1password-beta 1password-cli gnome-keyring \
    pinta xournalpp localsend-bin
fi

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-sync-applications || true
