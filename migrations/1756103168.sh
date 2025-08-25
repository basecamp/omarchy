echo "Allow pacman -Sy without sudo to easier installs"

sudo tee /etc/sudoers.d/repositories >/dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/pacman -Sy
EOF
sudo chmod 440 /etc/sudoers.d/repositories
