sudo mkdir -p /etc/sddm.conf.d

if [ ! -f /etc/sddm.conf.d/autologin.conf ]; then
  cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=hyprland-uwsm

[Theme]
Current=breeze
EOF
fi

echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sddm" | sudo tee /etc/sudoers.d/allow-passwordless-restart-sddm

chrootable_systemctl_enable sddm.service
