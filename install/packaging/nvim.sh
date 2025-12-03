# Only if nvim installed.
if pacman -Q omarchy-nvim &>/dev/null; then
  # Includes lazyvim and the themes
  omarchy-nvim-setup
fi
