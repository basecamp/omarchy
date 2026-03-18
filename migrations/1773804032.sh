echo "Add Ctrl+c imv binding to copy current image to clipboard"

if [[ ! -f ~/.config/imv/config ]]; then
  mkdir -p ~/.config/imv
  cp "$OMARCHY_PATH/config/imv/config" ~/.config/imv/config
fi

if ! grep -Fq '<Ctrl+c> = exec wl-copy < $imv_current_file' ~/.config/imv/config; then
  printf '\n# Copy the current image to the clipboard\n<Ctrl+c> = exec wl-copy < $imv_current_file\n' >>"$HOME/.config/imv/config"
fi
