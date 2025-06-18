# Use dark mode for QT apps too (like VLC and kdenlive)
sudo pacman -S --noconfirm kvantum-qt5

# Prefer dark mode everything
sudo pacman -S --noconfirm gnome-themes-extra # Adds Adwaita-dark theme
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Setup theme links
mkdir -p ~/.config/omarchy/themes
for f in ~/.local/share/omarchy/themes/*; do ln -s "$f" ~/.config/omarchy/themes/; done

# Set initial theme
ln -snf ~/.config/omarchy/themes/tokyo-night ~/.config/omarchy/current-theme
source ~/.local/share/omarchy/themes/tokyo-night/backgrounds.sh
ln -snf ~/.config/omarchy/backgrounds/tokyo-night ~/.config/omarchy/current-backgrounds

# Set specific app links for current theme
ln -snf ~/.config/omarchy/current-theme/wofi.css ~/.config/wofi/style.css
ln -snf ~/.config/omarchy/current-theme/neovim.lua ~/.config/nvim/lua/plugins/theme.lua
