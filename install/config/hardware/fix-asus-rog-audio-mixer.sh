# Fix audio volume on Asus ROG laptops by using a soft mixer.

if [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == "ASUSTeK COMPUTER INC." ]] &&
   grep -q "ROG" /sys/class/dmi/id/product_family 2>/dev/null; then

  mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
  cp $OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf ~/.config/wireplumber/wireplumber.conf.d/
  rm -rf ~/.local/state/wireplumber/default-routes
fi
