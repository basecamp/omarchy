echo "Update terminal scrolltouchpad setting to Hyprland 0.53 style"

if grep -q "scrolltouchpad" ~/.config/hypr/input.conf; then
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), class:\(([^)]+)\)$/windowrule = match:class (\2), scroll_touchpad \1/' ~/.config/hypr/input.conf
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), class:([^ ]+)$/windowrule = match:class \2, scroll_touchpad \1/' ~/.config/hypr/input.conf
  sed -Ei 's/^windowrule = scrolltouchpad ([^,]+), tag:terminal$/windowrule = match:class (Alacritty|kitty), scroll_touchpad 1.5\nwindowrule = match:class com.mitchellh.ghostty, scroll_touchpad 0.2/' ~/.config/hypr/input.conf
fi

# Ensure we restart to pair new Hyprland settings with new version
omarchy-state set reboot-required
