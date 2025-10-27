echo -e "Offer new Omarchy hotkeys\n"

cat <<EOF
* Add SUPER + C / V for unified clipboard in both terminal and other apps
* Add SUPER + CTRL + V for clipboard manager
* Move fullscreen from F11 to SUPER + F
* Keep terminal on SUPER + RETURN
* Move app keys from SUPER + [LETTER] to SHIFT + SUPER + [LETTER]
* Move toggling tiling/floating to SUPER + T
EOF

echo -e "\nSwitching to new hotkeys will change your existing bindings.\nThe old ones will be backed up as ~/.config/hypr/bindings.conf.bak\n"

if gum confirm "Switch to new hotkeys?"; then
  cp ~/.config/hypr/bindings.conf ~/.config/hypr/bindings.conf.bak

  sed -i 's/SUPER SHIFT,/SUPER SHIFT ALT,/g' ~/.config/hypr/bindings.conf
  sed -i 's/SUPER,/SUPER SHIFT,/g' ~/.config/hypr/bindings.conf
  sed -i 's/SUPER SHIFT, return, Terminal/SUPER, RETURN, Terminal/gI' ~/.config/hypr/bindings.conf
  sed -i 's/SUPER ALT,/SUPER SHIFT ALT,/g' ~/.config/hypr/bindings.conf
  sed -i 's/SUPER CTRL,/SUPER SHIFT CTRL,/g' ~/.config/hypr/bindings.conf
  sed -i 's/SUPER SHIFT ALT, G, Google Messages/SUPER SHIFT CTRL, G, Google Messages/g' ~/.config/hypr/bindings.conf

  sed -i 's|source = ~/.local/share/omarchy/default/hypr/bindings/tiling\.conf|source = ~/.local/share/omarchy/default/hypr/bindings/clipboard.conf\
source = ~/.local/share/omarchy/default/hypr/bindings/tiling-v2.conf|' ~/.config/hypr/hyprland.conf
fi
