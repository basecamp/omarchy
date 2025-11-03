# Allow the user to change the branding for fastfetch and screensaver
mkdir -p ~/.config/omarchy/branding
CURRENT_THEME_DIR="$HOME/.config/omarchy/current/theme"

# Handle about.txt (for fastfetch) - check theme first, then defaults
if [[ -f "$CURRENT_THEME_DIR/about.txt" ]]; then
  cp "$CURRENT_THEME_DIR/about.txt" ~/.config/omarchy/branding/about.txt
elif [[ ! -f ~/.config/omarchy/branding/about.txt ]] && [[ -f ~/.local/share/omarchy/icon.txt ]]; then
  cp ~/.local/share/omarchy/icon.txt ~/.config/omarchy/branding/about.txt
fi

# Handle screensaver.txt - check theme first, then defaults
if [[ -f "$CURRENT_THEME_DIR/screensaver.txt" ]]; then
  cp "$CURRENT_THEME_DIR/screensaver.txt" ~/.config/omarchy/branding/screensaver.txt
elif [[ ! -f ~/.config/omarchy/branding/screensaver.txt ]] && [[ -f ~/.local/share/omarchy/logo.txt ]]; then
  cp ~/.local/share/omarchy/logo.txt ~/.config/omarchy/branding/screensaver.txt
fi
