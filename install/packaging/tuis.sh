OMARCHY_DESCRIPTION="TUIs"

omarchy_install() {
  ICON_DIR="$HOME/.local/share/applications/icons"

  omarchy-tui-install "Disk Usage" "bash -c 'dust -r; read -n 1 -s'" float "$ICON_DIR/Disk Usage.png"
  omarchy-tui-install "Docker" "lazydocker" tile "$ICON_DIR/Docker.png"
}

omarchy_verify() {
  [[ -f "$HOME/.local/share/applications/Disk Usage.desktop" ]] || add_error "Disk Usage TUI not installed"
  [[ -f "$HOME/.local/share/applications/Docker.desktop" ]] || add_error "Docker TUI not installed"
}
