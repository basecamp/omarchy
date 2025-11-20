echo "Set \$TERMINAL and \$EDITOR in ~/.config/uwsm/default so entire system can rely on it"

# Set terminal and editor default in uwsm
omarchy-refresh-config uwsm/default
omarchy-refresh-config uwsm/env
omarchy-state set reboot-required

# Ensure scrolltouchpad setting applies to all terminals
if grep -q "scrolltouchpad 1.5, class:Alacritty" ~/.config/hypr/input.conf; then
  sed -i 's/windowrule = scrolltouchpad 1\.5, class:Alacritty/windowrule = scrolltouchpad 1.5, tag:terminal/' ~/.config/hypr/input.conf
fi

# Use default editor for keybinding
if grep -q "bindd = SUPER, N, Neovim" ~/.config/hypr/bindings.conf; then
  sed -i '/SUPER, N, Neovim, exec/ c\bindd = SUPER, N, Editor, exec, omarchy-launch-editor' ~/.config/hypr/bindings.conf
fi

# Use default terminal for keybinding
if grep -q "terminal = uwsm app" ~/.config/hypr/bindings.conf; then
  sed -Ei '/terminal = uwsm[- ]app -- alacritty/ c\$terminal = uwsm-app -- $TERMINAL' ~/.config/hypr/bindings.conf
fi
