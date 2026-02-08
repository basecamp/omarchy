sudo mkdir -p /etc/greetd

cat <<EOF | sudo tee /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-user-session --asterisks --cmd \"uwsm start -e -D Hyprland hyprland.desktop\""
user = "greeter"

[initial_session]
command = "uwsm start -e -D Hyprland hyprland.desktop"
user = $USER
EOF

# Disable conflicting display managers
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable lightdm.service 2>/dev/null || true

sudo systemctl enable greetd.service
