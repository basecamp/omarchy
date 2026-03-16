echo "Replace Impala with nettui for Omarchy network controls"

if omarchy-cmd-missing nettui; then
  omarchy-pkg-add nettui
fi

sudo systemctl enable --now systemd-networkd.service
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

if omarchy-cmd-present impala; then
  omarchy-pkg-drop impala
fi
