if [[ ! -f ~/.local/state/omarchy/bare.mode ]]; then
  echo "Offer to swap Spotify GUI to TUI"

  if command -v spotify >/dev/null && ! command -v spotify_player >/dev/null; then
    if gum confirm "Replace Spotify GUI with TUI?"; then
      yay -Sy --noconfirm spotify-player
      yay -Rns --noconfirm spotify

      sed -i -E 's|bind = (.+), exec, .*spotify|bind = \1, exec, $terminal -e spotify_player|' ~/.config/hypr/hyprland.conf
    fi
  fi
fi
