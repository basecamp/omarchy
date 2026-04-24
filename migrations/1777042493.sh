echo "Deprioritize iPhone USB tethering below Wi-Fi so plugging in an iPhone to charge does not hijack the default route"

sudo cp $OMARCHY_PATH/default/systemd/network/15-ipheth.network /etc/systemd/network/
sudo networkctl reload 2>/dev/null || sudo systemctl reload systemd-networkd 2>/dev/null || true
