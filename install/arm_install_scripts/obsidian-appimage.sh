#!/bin/bash

# Install Obsidian AppImage for ARM
echo "Installing Obsidian AppImage for ARM..."

# Check if Obsidian is already installed
if [ -f /usr/bin/obsidian ]; then
  echo "Obsidian already installed, skipping"
  return 0
fi

# Create omarchy applications directory
mkdir -p ~/.local/share/omarchy/applications/icons

# Download the latest ARM64 AppImage
OBSIDIAN_VERSION="1.9.12"
OBSIDIAN_URL="https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/Obsidian-${OBSIDIAN_VERSION}-arm64.AppImage"

echo "Downloading Obsidian ${OBSIDIAN_VERSION} ARM64 AppImage..."
sudo curl -L "$OBSIDIAN_URL" -o /usr/bin/obsidian
sudo chmod +x /usr/bin/obsidian

# Create desktop entry for omarchy application management
if [ ! -f ~/.local/share/omarchy/applications/obsidian.desktop ]; then
  cat > ~/.local/share/omarchy/applications/obsidian.desktop << 'EOF'
[Desktop Entry]
Name=Obsidian
Comment=A powerful knowledge base that works on top of a local folder of plain text Markdown files
Exec=/usr/bin/obsidian
Icon=obsidian
Type=Application
Categories=Office;TextEditor;Development;
MimeType=text/markdown;text/x-markdown;
StartupNotify=true
StartupWMClass=obsidian
EOF
fi

# Download and install icon
echo "Downloading Obsidian icon..."
ICON_URL="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/obsidian.png"
curl -L "$ICON_URL" -o ~/.local/share/omarchy/applications/icons/obsidian.png

# Resize icon to 48x48 for omarchy's icon system if convert is available
if command -v convert &>/dev/null; then
  convert ~/.local/share/omarchy/applications/icons/obsidian.png -resize 48x48 ~/.local/share/omarchy/applications/icons/obsidian.png
fi

# Refresh applications using omarchy's system
if command -v omarchy-refresh-applications &>/dev/null; then
  omarchy-refresh-applications
fi

echo "Obsidian AppImage installed successfully"
