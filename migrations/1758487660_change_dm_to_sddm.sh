echo "Change display manager to SDDM"

sudo pacman -S --needed --noconfirm sddm libsecret gnome-keyring

sudo mkdir -p /etc/sddm.conf.d

cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=hyprland-uwsm

[Theme]
Current=breeze
EOF

sudo systemctl disable omarchy-seamless-login.service
sudo systemctl unmask plymouth-quit-wait.service
sudo systemctl enable getty@tty1.service
sudo systemctl enable sddm.service
sudo systemctl daemon-reload

sudo rm -f /usr/local/bin/seamless-login
sudo rm -f /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf
sudo rm -f /etc/systemd/system/omarchy-seamless-login.service
