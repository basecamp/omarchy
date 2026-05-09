echo "Add Foot terminal window rules where terminals are described"

if [[ -f ~/.config/hypr/input.conf ]]; then
  sed -Ei 's/match:class \(Alacritty\|kitty\)/match:class (Alacritty|kitty|foot)/' ~/.config/hypr/input.conf
fi

if [[ -f ~/.config/hypr/apps/terminals.conf ]]; then
  sed -Ei 's/match:class \(Alacritty\|kitty\|com\.mitchellh\.ghostty\)/match:class (Alacritty|kitty|com.mitchellh.ghostty|foot)/' ~/.config/hypr/apps/terminals.conf
fi
