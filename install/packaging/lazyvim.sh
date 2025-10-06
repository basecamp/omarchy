OMARCHY_DESCRIPTION="LazyVim"

omarchy_install() {
  if [[ ! -d "$HOME/.config/nvim" ]]; then
      omarchy-lazyvim-setup
  fi
}

omarchy_verify() {
  [[ -d "$HOME/.config/nvim" ]] || add_error "Neovim config directory missing"
}
