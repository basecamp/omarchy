OMARCHY_DESCRIPTION="Omarchy Font"

omarchy_install() {
  # Omarchy logo in a font for Waybar use
  mkdir -p ~/.local/share/fonts
  cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
  fc-cache
}

omarchy_verify() {
  [[ -d ~/.local/share/fonts ]] || add_error "Fonts directory missing"
  [[ -f ~/.local/share/fonts/omarchy.ttf ]] || add_error "Omarchy font missing"
}
