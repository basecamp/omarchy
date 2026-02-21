echo "Add Logout option to system menu"

sudo cp -r $OMARCHY_PATH/default/sddm/omarchy /usr/share/sddm/themes/omarchy

if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
  sudo sed -i 's/^Current=.*/Current=omarchy/' /etc/sddm.conf.d/autologin.conf
fi
