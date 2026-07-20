echo "Install nautilus-open-any-terminal"

omarchy-pkg-add nautilus-open-any-terminal

source $OMARCHY_PATH/install/config/nautilus-open-any-terminal.sh

if [[ -f ~/.config/ghostty/config ]] && ! grep -q "^gtk-single-instance" ~/.config/ghostty/config; then
  sed -i "/^gtk-toolbar-style/a gtk-single-instance = false" ~/.config/ghostty/config
fi
