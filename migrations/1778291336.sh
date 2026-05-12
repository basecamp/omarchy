echo "Persist Bluetooth power state across reboots"

sudo sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
