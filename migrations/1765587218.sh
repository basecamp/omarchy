echo "Add custom share portal picker"
omarchy-pkg-add hyprland-preview-share-picker

if ! grep -q "custom_picker_binary" ~/.config/hypr/xdph.conf; then
    sed -i '/screencopy {/a\    custom_picker_binary = hyprland-preview-share-picker' ~/.config/hypr/xdph.conf
fi
