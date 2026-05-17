echo "Migrate clipboard manager shortcut to use Quickshell clipboard picker"

if [[ -f ~/.config/hypr/bindings/clipboard.lua ]]; then
  sed -i 's/walker -m clipboard/omarchy-shell-ipc shell toggle omarchy.clipboard-picker "{}"/' ~/.config/hypr/bindings/clipboard.lua
fi
