echo "Restricting passwordless timedatectl access to timezone updates"

sudo tee /etc/sudoers.d/omarchy-tzupdate >/dev/null <<EOF
%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl set-timezone *
EOF
sudo chmod 0440 /etc/sudoers.d/omarchy-tzupdate
