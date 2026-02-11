echo "DedSecOS full UI overhaul — refresh all configs, set up EWW HUD, rofi menu, refresh Plymouth"

# Install new dependencies
omarchy-pkg-aur-add eww

omarchy-pkg-add rofi

# Copy EWW config
mkdir -p ~/.config/eww
cp -f ~/.local/share/omarchy/config/eww/eww.yuck ~/.config/eww/eww.yuck
cp -f ~/.local/share/omarchy/config/eww/eww.scss ~/.config/eww/eww.scss

# Copy rofi config
mkdir -p ~/.config/rofi
cp -f ~/.local/share/omarchy/config/rofi/config.rasi ~/.config/rofi/config.rasi
cp -f ~/.local/share/omarchy/config/rofi/dedsec.rasi ~/.config/rofi/dedsec.rasi
cp -f ~/.local/share/omarchy/config/rofi/dedsec-drun.rasi ~/.config/rofi/dedsec-drun.rasi


# Copy updated screensaver text
cp -f ~/.local/share/omarchy/screensaver.txt ~/.config/omarchy/branding/screensaver.txt

# Refresh all changed configs
omarchy-refresh-hyprland
omarchy-refresh-hyprlock
omarchy-refresh-waybar
omarchy-refresh-walker
omarchy-refresh-swayosd
omarchy-refresh-plymouth
omarchy-refresh-limine

# Copy updated configs that don't have refresh commands
omarchy-refresh-config mako/config
omarchy-refresh-config starship.toml
omarchy-refresh-config fastfetch/config.jsonc

# Re-apply current theme to render updated templates
omarchy-theme-refresh

# Start EWW HUD
eww open ctos-hud &>/dev/null || true

