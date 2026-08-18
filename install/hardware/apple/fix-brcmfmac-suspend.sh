# BCM4350 and BCM43602 firmware can stop answering after S3 resume on Apple
# hardware. Once that happens, brcmfmac times out on ioctls, NetworkManager
# cannot initialize its supplicant interface, and every scan fails until the
# firmware is reinitialized.
#
# Unbind the device before sleep so its unreliable firmware power transition is
# bypassed, then bind it after wake so NetworkManager gets a freshly initialized
# radio. Keep this on the confirmed Apple BCM4350/BCM43602 PCI IDs instead of
# resetting T2-era brcmfmac devices, which need the opposite treatment.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if [[ $sys_vendor == Apple* ]] &&
  lspci -nn | grep -E "14e4:(43a3|43ba|43bb|43bc)" >/dev/null; then
  echo "Detected Apple BCM4350/BCM43602 Wi-Fi; resetting its driver around sleep"

  sudo install -Dm644 \
    "$OMARCHY_PATH/install/hardware/apple/omarchy-brcmfmac-suspend.service" \
    /etc/systemd/system/omarchy-brcmfmac-suspend.service
  sudo systemctl enable omarchy-brcmfmac-suspend.service
fi
