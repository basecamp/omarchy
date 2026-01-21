if [[ ! -d "$HOME/.config/nvim" ]]; then
  # Auto-answer yes to any prompts during setup
  yes | omarchy-nvim-setup
fi
