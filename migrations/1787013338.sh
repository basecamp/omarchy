echo "Reset Apple BCM4350/BCM43602 Wi-Fi around sleep"

# The installer only reaches new systems. Existing Apple BCM4350 and BCM43602
# installs can leave the radio firmware unresponsive after resume, which also
# makes later suspend attempts fail in brcmf_pcie_pm_enter_D3 until reboot.
dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
service_source="${OMARCHY_BRCMFMAC_SUSPEND_SERVICE_SOURCE:-$OMARCHY_PATH/install/hardware/apple/omarchy-brcmfmac-suspend.service}"
service_target="${OMARCHY_BRCMFMAC_SUSPEND_SERVICE_TARGET:-/etc/systemd/system/omarchy-brcmfmac-suspend.service}"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if [[ $sys_vendor != Apple* ]] ||
  ! lspci -nn | grep -E "14e4:(43a3|43ba|43bb|43bc)" >/dev/null; then
  exit 0
fi

if ! cmp -s "$service_source" "$service_target"; then
  sudo install -Dm644 "$service_source" "$service_target"
fi

if ! systemctl is-enabled --quiet omarchy-brcmfmac-suspend.service 2>/dev/null; then
  sudo systemctl enable omarchy-brcmfmac-suspend.service
fi
