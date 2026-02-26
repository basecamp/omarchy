echo "Add Logout option to system menu"

omarchy-refresh-sddm

if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
  sudo sed -i 's/^Current=.*/Current=omarchy/' /etc/sddm.conf.d/autologin.conf
fi
