echo "Add Super+Shift+Return binding for browser"

if [[ -f ~/.config/hypr/bindings.conf ]] && ! grep -q "SUPER SHIFT, RETURN.*Browser" ~/.config/hypr/bindings.conf; then
  sed -i '/^bindd = SUPER, RETURN, Terminal/a bindd = SUPER SHIFT, RETURN, Browser, exec, omarchy-launch-browser' ~/.config/hypr/bindings.conf
fi
