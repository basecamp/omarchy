# Use dark mode for QT apps too (like kdenlive)
sudo pacman -S --noconfirm kvantum-qt5

# Install GTK themes
sudo pacman -S --noconfirm gnome-themes-extra # Adds Adwaita themes

# Initial theme settings will be applied when setting default theme below

# Setup theme links
mkdir -p ~/.config/omarchy/themes
for f in ~/.local/share/omarchy/themes/*; do ln -s "$f" ~/.config/omarchy/themes/; done

# Set initial theme
mkdir -p ~/.config/omarchy/current
ln -snf ~/.config/omarchy/themes/tokyo-night ~/.config/omarchy/current/theme
source ~/.local/share/omarchy/themes/tokyo-night/backgrounds.sh
ln -snf ~/.config/omarchy/backgrounds/tokyo-night ~/.config/omarchy/current/backgrounds
ln -snf ~/.config/omarchy/current/backgrounds/1-Pawel-Czerwinski-Abstract-Purple-Blue.jpg ~/.config/omarchy/current/background

# Apply theme configuration
THEME_CONF="$HOME/.config/omarchy/themes/tokyo-night/theme.conf"
if [[ -f "$THEME_CONF" ]]; then
  source "$THEME_CONF"
  
  # Apply GTK settings
  [[ -n "$gtk_theme" ]] && gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  [[ -n "$gtk_color_scheme" ]] && gsettings set org.gnome.desktop.interface color-scheme "$gtk_color_scheme"
  [[ -n "$icon_theme" ]] && gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
  [[ -n "$cursor_theme" ]] && gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme"
  
  # Create theme environment file
  echo "export GTK_THEME=\"$gtk_theme\"" > "$HOME/.config/omarchy/current/theme.env"
fi

# Generate desktop files with correct theme
~/.local/share/omarchy/bin/omarchy-update-desktop-files

# Set specific app links for current theme
ln -snf ~/.config/omarchy/current/theme/wofi.css ~/.config/wofi/style.css
ln -snf ~/.config/omarchy/current/theme/neovim.lua ~/.config/nvim/lua/plugins/theme.lua
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config
