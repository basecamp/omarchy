echo "Re-run scrolltouchpad migration for configs with trailing whitespace"

if grep -q "scrolltouchpad" ~/.config/hypr/input.conf; then
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), class:\(([^)]+)\)\s*$/windowrule = match:class (\2), scroll_touchpad \1/' ~/.config/hypr/input.conf
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), class:([^ ]+)\s*$/windowrule = match:class \2, scroll_touchpad \1/' ~/.config/hypr/input.conf
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), tag:terminal\s*$/windowrule = match:class (Alacritty|kitty), scroll_touchpad 1.5\nwindowrule = match:class com.mitchellh.ghostty, scroll_touchpad 0.2/' ~/.config/hypr/input.conf

  omarchy-state set reboot-required
fi
