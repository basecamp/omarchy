# Persist last power state across reboots (default AutoEnable=true overrides it)
if [[ -f /etc/bluetooth/main.conf ]]; then
  sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
fi
