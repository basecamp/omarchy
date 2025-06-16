# Copy over Omarchy configs
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Copy over Omarchy applications
mkdir -p ~/.local/share/applications
cp -R ~/.local/share/omarchy/applications/* ~/.local/share/applications/

# Use default bashrc from Omarchy
echo "source ~/.local/share/omarchy/default/bash/rc" >~/.bashrc

# Login directly as user, rely on disk encryption + hyprlock for security
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USER --noclear %I \$TERM
EOF

# Set common git aliases
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global pull.rebase true
