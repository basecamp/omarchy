sudo mkdir -p /etc/sddm.conf.d

# Install omarchy SDDM theme
sudo cp -r $OMARCHY_PATH/default/sddm/omarchy /usr/share/sddm/themes/omarchy

if [[ ! -f /etc/sddm.conf.d/autologin.conf ]]; then
  cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=hyprland-uwsm

[Theme]
Current=omarchy
EOF
fi

# Don't use chrootable here as --now will cause issues for manual installs
sudo systemctl enable sddm.service
