echo "Switch to Omarchy Chromium for synchronized theme switching"

set_theme_colors() {
  if [[ -f ~/.config/omarchy/current/theme/chromium.theme ]] && command -v chromium &>/dev/null; then
    chromium --no-startup-window --set-theme-color="$(<~/.config/omarchy/current/theme/chromium.theme)"
  else
    # Use a default, neutral grey if theme doesn't have a color
    chromium --no-startup-window --set-theme-color="28,32,39"
  fi
}

if command -v chromium &>/dev/null; then
  yay -Rns --noconfirm chromium
  yay -Sy --noconfirm omarchy-chromium-bin

  if pgrep -x chromium; then
    if gum confirm "Chromium must be restarted. Ready?"; then
      pkill -x chromium
      set_theme_colors
    fi
  else
    set_theme_colors
  fi
fi
