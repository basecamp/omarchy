echo "Install tzupdate, enable automatic timezone sync at login, and configure passwordless sudo for timezone updates (tzupdate, timedatectl set-timezone) for all wheel users."

# Install tzupdate if not present
yay -S --noconfirm --needed tzupdate

# Ensure the current user is in the wheel group
if ! groups $USER | grep -qw wheel; then
  echo "Adding $USER to wheel group (admin privileges required)..."
  sudo usermod -aG wheel $USER
  echo -e "\e[32m$USER added to wheel group. You may need to log out and back in for this to take effect.\e[0m"
fi

# Create sudoers file for tzupdate and timedatectl set-timezone
SUDOERS_FILE="/etc/sudoers.d/omarchy-tzupdate"
SUDOERS_CONTENT="%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl set-timezone *"

echo "$SUDOERS_CONTENT" | sudo tee "$SUDOERS_FILE" >/dev/null
sudo chmod 0440 "$SUDOERS_FILE"

echo -e "\e[32mPasswordless sudo for timezone updates is now enabled for all wheel users.\e[0m"

# Create systemd user service for tzupdate
cat > ~/.config/systemd/user/omarchy-tzupdate.service <<EOF
[Unit]
Description=Update timezone using tzupdate at login
After=network-online.target

[Service]
Type=oneshot
ExecStart=$(command -v tzupdate)

[Install]
WantedBy=default.target
EOF

# Enable the service for the user
systemctl --user daemon-reload
systemctl --user enable omarchy-tzupdate.service 