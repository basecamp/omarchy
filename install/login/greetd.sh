sudo mkdir -p /etc/greetd

# Install greetd config with autologin
sudo cp "$OMARCHY_PATH/config/greetd/config-tuigreet.toml" /etc/greetd/config.toml
printf '\n[initial_session]\ncommand = "UWSM_SILENT_START=2 uwsm start -e -D Hyprland hyprland.desktop"\nuser = "%s"\n' "$USER" | sudo tee -a /etc/greetd/config.toml >/dev/null

# Install regreet theme config
sudo cp "$OMARCHY_PATH/config/greetd/regreet.toml" /etc/greetd/regreet.toml

# Keep Plymouth splash visible until Hyprland takes over the display
sudo mkdir -p /etc/systemd/system/greetd.service.d
cat <<EOF | sudo tee /etc/systemd/system/greetd.service.d/no-wait-plymouth.conf
[Unit]
After=
After=systemd-user-sessions.service
After=getty@tty1.service
EOF

sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d
cat <<EOF | sudo tee /etc/systemd/system/plymouth-quit.service.d/delay-for-compositor.conf
[Unit]
After=greetd.service

[Service]
ExecStart=
ExecStart=-/usr/bin/plymouth quit --retain-splash
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 30); do pgrep -x Hyprland >/dev/null && break; sleep 0.5; done; sleep 1'
EOF

sudo systemctl daemon-reload

# Disable conflicting display managers
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable lightdm.service 2>/dev/null || true

sudo systemctl enable greetd.service
