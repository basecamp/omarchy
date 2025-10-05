#!/bin/bash
set -e

error_exit() {
  echo -e "\033[31mERROR: Migration failed! Manual intervention required.\033[0m" >&2
  echo -e "\033[31mDO NOT REBOOT - System may be in inconsistent state until the error is fixed.\033[0m" >&2
  exit 1
}

trap error_exit ERR

echo "Change display manager to SDDM"

sudo pacman -S --needed --noconfirm sddm libsecret gnome-keyring

for pkg in sddm libsecret gnome-keyring; do
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    echo -e "\033[31mError: Package '$pkg' is not installed\033[0m" >&2
    error_exit
  fi
done

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

if systemctl is-enabled omarchy-seamless-login.service >/dev/null 2>&1; then
  echo -e "\033[31mError: omarchy-seamless-login.service is still enabled\033[0m" >&2
  error_exit
fi

if systemctl is-masked plymouth-quit-wait.service >/dev/null 2>&1; then
  echo -e "\033[31mError: plymouth-quit-wait.service is still masked\033[0m" >&2
  error_exit
fi

if ! systemctl is-enabled getty@tty1.service >/dev/null 2>&1; then
  echo -e "\033[31mError: getty@tty1.service is not enabled\033[0m" >&2
  error_exit
fi

if ! systemctl is-enabled sddm.service >/dev/null 2>&1; then
  echo -e "\033[31mError: sddm.service is not enabled\033[0m" >&2
  error_exit
fi

sudo rm -f /usr/local/bin/seamless-login
sudo rm -f /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf
sudo rm -f /etc/systemd/system/omarchy-seamless-login.service

echo "Migration completed successfully"
