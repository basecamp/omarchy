# Remove existing nvim config (omarchy-nvim-setup will recreate it)
# This avoids the interactive backup/overwrite prompt
if [[ -d "$HOME/.config/nvim" ]]; then
  backup_name="$HOME/.config/nvim.backup"
  if [[ -d "$backup_name" ]]; then
    backup_name="$HOME/.config/nvim.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$HOME/.config/nvim" "$backup_name"
fi

omarchy-nvim-setup
