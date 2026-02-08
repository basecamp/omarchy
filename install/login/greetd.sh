sudo mkdir -p /etc/greetd

if [ ! -f /etc/greetd/config.toml ]; then
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
fi

sudo systemctl enable greetd.service
