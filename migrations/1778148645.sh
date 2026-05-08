echo "Configure SDDM to use Wayland for the greeter"

sudo cp "$OMARCHY_PATH/default/sddm/hyprland.conf" /usr/share/sddm/hyprland.conf
sudo mkdir -p /etc/sddm.conf.d
cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland.conf >/dev/null
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.conf
EOF
