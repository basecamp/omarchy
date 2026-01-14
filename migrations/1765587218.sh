echo "Add custom share portal picker"
omarchy-pkg-add hyprland-preview-share-picker

mkdir -p ~/.config/hyprland-preview-share-picker
omarchy-refresh-config hyprland-preview-share-picker/config.yaml

if ! grep -q "custom_picker_binary" ~/.config/hypr/xdph.conf; then
  sed -i '/screencopy {/a\    custom_picker_binary = hyprland-preview-share-picker' ~/.config/hypr/xdph.conf
fi

sleep 1
killall -e xdg-desktop-portal-hyprland
killall -e xdg-desktop-portal-wlr
killall xdg-desktop-portal
/usr/lib/xdg-desktop-portal-hyprland &
sleep 2
/usr/lib/xdg-desktop-portal &
