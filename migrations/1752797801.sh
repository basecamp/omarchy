echo "fix omarchy seamless login service"
sed -i 's/Restart=always/Restart=on-success/' /etc/systemd/system/omarchy-seamless-login.service
sudo systemctl daemon-reload

if ! command -v pactree &>/dev/null; then
  yay -S --noconfirm --needed pacman-contrib
fi

echo "remove package that can break Hyprland"
if pacman -Qi hyprutils-git &>/dev/null; then
  if pacman -Qi hyprsunset-git &>/dev/null; then
    # basically leftovers from other Hyprland installations lihe JaCoolit that can mess things up
    yay -R --noconfirm hyprsunset-git
    yay -S --noconfirm hyprutils hyprsunset
  else
    yay -S --noconfirm hyprutils
  fi
fi
