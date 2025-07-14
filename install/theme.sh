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

# Apply theme configuration from theme.toml
THEME_TOML="$HOME/.config/omarchy/themes/tokyo-night/theme.toml"

if [[ -f "$THEME_TOML" ]]; then
  # Parse TOML file using tomlq
  gtk_theme=$(tomlq -r '.gtk.theme' "$THEME_TOML")
  gtk_color_scheme=$(tomlq -r '.gtk.color_scheme' "$THEME_TOML")
  icon_theme=$(tomlq -r '.icons.theme' "$THEME_TOML")
  cursor_theme=$(tomlq -r '.icons.cursor_theme' "$THEME_TOML")
  
  # Apply GTK settings
  [[ -n "$gtk_theme" && "$gtk_theme" != "null" ]] && gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  [[ -n "$gtk_color_scheme" && "$gtk_color_scheme" != "null" ]] && gsettings set org.gnome.desktop.interface color-scheme "$gtk_color_scheme"
  [[ -n "$icon_theme" && "$icon_theme" != "null" ]] && gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
  [[ -n "$cursor_theme" && "$cursor_theme" != "null" ]] && gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme"
  
  # Create theme environment file
  echo "export GTK_THEME=\"$gtk_theme\"" > "$HOME/.config/omarchy/current/theme.env"
  
  # Parse and set environment variables
  env_vars=$(tomlq -r '.env // {}' "$THEME_TOML")
  if [[ "$env_vars" != "{}" && "$env_vars" != "null" ]]; then
    # Export each environment variable
    while IFS= read -r line; do
      key=$(echo "$line" | cut -d: -f1 | xargs | tr -d '"')
      value=$(echo "$line" | cut -d: -f2- | xargs | tr -d '"')
      if [[ -n "$key" && -n "$value" ]]; then
        echo "export $key=\"$value\"" >> "$HOME/.config/omarchy/current/theme.env"
      fi
    done < <(echo "$env_vars" | jq -r 'to_entries[] | "\(.key):\(.value)"')
  fi
else
  echo "Error: theme.toml not found for tokyo-night" >&2
  exit 1
fi

# Generate desktop files with correct theme
~/.local/share/omarchy/bin/omarchy-update-desktop-files

# Set specific app links for current theme
ln -snf ~/.config/omarchy/current/theme/neovim.lua ~/.config/nvim/lua/plugins/theme.lua
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config
