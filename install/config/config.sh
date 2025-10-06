OMARCHY_DESCRIPTION="Config Files"

omarchy_install() {
  # Copy over Omarchy configs
  mkdir -p ~/.config
  cp -R ~/.local/share/omarchy/config/* ~/.config/

  # Use default bashrc from Omarchy
  cp ~/.local/share/omarchy/default/bashrc ~/.bashrc
}

omarchy_verify() {
  [[ -d ~/.config ]] || add_error "Config directory missing"
  [[ -f ~/.bashrc ]] || add_error "Bashrc file missing"

  [[ -d ~/.config/hypr ]] || add_error "Hypr config missing"
  [[ -d ~/.config/waybar ]] || add_error "Waybar config missing"
}
