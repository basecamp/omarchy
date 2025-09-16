echo "Add SUPER + SHIFT + B to start browser in private mode"

if [[ -f ~/.config/hypr/bindings.conf ]] && grep -q "SUPER, B, Browser, exec" ~/.config/hypr/bindings.conf; then
  sed -i '/^bindd = SUPER, B, Browser, exec, \$browser$/a\
bindd = SUPER SHIFT, B, Browser (private), exec, $browser --private' ~/.config/hypr/bindings.conf
fi
