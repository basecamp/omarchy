echo "Migrate emoji picker shortcut to use Quickshell emoji picker"

if [[ -f ~/.config/hypr/bindings/utilities.lua ]]; then
  sed -i 's/omarchy-launch-walker -m symbols/omarchy-shell-ipc shell toggle omarchy.emoji-picker "{}"/' ~/.config/hypr/bindings/utilities.lua
fi

if [[ -f ~/.config/hypr/bindings.lua ]]; then
  sed -i 's/omarchy-launch-walker -m symbols/omarchy-shell-ipc shell toggle omarchy.emoji-picker "{}"/' ~/.config/hypr/bindings.lua
fi
