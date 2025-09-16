echo "Ensure $TERMINAL is set in uwsm env so entire system can rely on it"

if ! grep -q "export TERMINAL" ~/.config/uwsm/env; then
  omarchy-refresh-config uwsm/env
  omarchy-state set relaunch-required
fi

if grep "scrolltouchpad 1.5, class:Alacritty" ~/.config/hypr/input.conf; then
  sed -i 's/windowrule = scrolltouchpad 1\.5, class:Alacritty/windowrule = scrolltouchpad 1.5, tag:terminals/' ~/.config/hypr/input.conf
fi
