# Install available packages from Fedora repos
sudo dnf install -y \
  libreoffice obs-studio kdenlive \
  pinta xournalpp

# Note: These packages need alternative installation methods on Fedora:
# - signal-desktop: install from Flathub or Signal website
# - spotify: install from Flathub or Spotify website
# - dropbox-cli: install from Dropbox website
# - zoom: install from Zoom website
# - obsidian-bin: install from Obsidian website or Flathub
# - typora: install from Typora website

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-sync-applications || true
