OMARCHY_DESCRIPTION="Branding Config"

omarchy_install() {
  mkdir -p ~/.config/omarchy/branding
  cp ~/.local/share/omarchy/icon.txt ~/.config/omarchy/branding/about.txt
  cp ~/.local/share/omarchy/logo.txt ~/.config/omarchy/branding/screensaver.txt
}

omarchy_verify() {
  [[ -d ~/.config/omarchy/branding ]] || add_error "Branding directory missing"
  [[ -f ~/.config/omarchy/branding/about.txt ]] || add_error "About branding file missing"
  [[ -f ~/.config/omarchy/branding/screensaver.txt ]] || add_error "Screensaver branding file missing"
}
