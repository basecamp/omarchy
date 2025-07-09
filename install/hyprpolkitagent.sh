yay -S --noconfirm --needed hyprpolkitagent

# Ensure hyprpolkitagent is running in dark mode
mkdir -p ~/.config/systemd/user/hyprpolkitagent.service.d
cat >~/.config/systemd/user/hyprpolkitagent.service.d/override.conf <<EOF
[Service]
Environment=GTK_THEME=Adwaita-dark
EOF
