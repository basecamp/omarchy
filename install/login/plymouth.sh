if [ "$(plymouth-set-default-theme)" != "omarchy" ]; then
  sudo cp -r "/usr/share/omarchy/default/plymouth" /usr/share/plymouth/themes/omarchy/
  sudo plymouth-set-default-theme omarchy
fi
