# T2 Macs' PCIe Wi-Fi (brcmfmac driving BCM4377/4378) times out entering D3
# during suspend, aborting the whole suspend/hibernate cycle and leaving the
# machine to retry indefinitely instead of ever sleeping. See
# default/systemd/system-sleep/t2-wifi-suspend for the failure and the fix.
#
# systemd-sleep only reads hooks from /usr/lib/systemd/system-sleep, so the
# hook has to land there rather than staying in $OMARCHY_PATH's copy of it.
if lspci -nn | grep "106b:180[12]" >/dev/null; then
  echo "Detected MacBook with T2 chip. Installing Wi-Fi suspend fix..."

  mkdir -p /usr/lib/systemd/system-sleep
  cp -p "$OMARCHY_PATH/default/systemd/system-sleep/t2-wifi-suspend" \
    /usr/lib/systemd/system-sleep/
fi
