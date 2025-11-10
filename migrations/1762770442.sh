echo "Slow down Ghostty mouse scrolling to match Alacritty"

if ! grep -q "mouse-scroll-multiplier" ~/.config/ghostty/config; then
  echo -e "\n# Slowdown mouse scrolling\nmouse-scroll-multiplier = 0.95" >> ~/.config/ghostty/config
fi
