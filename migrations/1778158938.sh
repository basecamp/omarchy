echo "Use a minimal Hyprland config for the SDDM Wayland greeter"

sudo cp "$OMARCHY_PATH/default/sddm/hyprland.conf" /usr/share/sddm/hyprland.conf
sudo mkdir -p /etc/sddm.conf.d
sudo sed -i 's|^CompositorCommand=Hyprland$|CompositorCommand=Hyprland --config /usr/share/sddm/hyprland.conf|' /etc/sddm.conf.d/10-wayland.conf
