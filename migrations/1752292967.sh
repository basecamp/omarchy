echo "Update to use UWSM and seamless login"

if cmd-missing uwsm; then
  sudo rm -f /etc/systemd/system/getty@tty1.service.d/override.conf
  sudo rmdir /etc/systemd/system/getty@tty1.service.d/ 2>/dev/null || true

  if [ -f "$HOME/.bash_profile" ]; then
    # Remove the specific line
    sed -i '/^\[\[ -z \$DISPLAY && \$(tty) == \/dev\/tty1 \]\] && exec Hyprland$/d' "$HOME/.bash_profile"
    echo "Cleaned up .bash_profile"
  fi

  if [ -f "$HOME/.config/environment.d/fcitx.conf" ]; then
    echo "Removing GTK_IM_MODULE from fcitx config for Wayland..."
    sed -i 's/^GTK_IM_MODULE=fcitx$//' "$HOME/.config/environment.d/fcitx.conf"
  fi

  source $OMARCHY_PATH/install/login/plymouth.sh
fi
