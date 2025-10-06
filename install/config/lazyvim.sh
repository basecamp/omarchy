OMARCHY_DESCRIPTION="LazyVim"

omarchy_install() {
  omarchy-lazyvim-setup
}

omarchy_verify() {
  [[ -d ~/.config/nvim ]] || add_error "Neovim config directory missing"
  [[ -d ~/.local/share/nvim/lazy ]] || add_error "LazyVim plugins directory missing"
}
