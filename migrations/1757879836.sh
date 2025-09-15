echo "Ensure .config/hypr/looknfeel.conf is available and included"

if [[ ! -f ~/.config/hypr/looknfeel.conf ]]; then
  cp $OMARCHY_PATH/config/hypr/looknfeel.conf ~/.config/hypr/looknfeel.conf
fi

if [[ -f ~/.config/hypr/hyprland.conf ]]; then
  grep -qx 'source = ~/.config/hypr/looknfeel.conf' ~/.config/hypr/hyprland.conf ||
    sed -i '/^source = ~\/.config\/hypr\/envs\.conf$/a source = ~/.config/hypr/looknfeel.conf' ~/.config/hypr/hyprland.conf
fi
