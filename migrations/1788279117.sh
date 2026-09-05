echo "Replace the YT6801 vendor DKMS driver with the upstream kernel driver"

mapfile -t yt6801_devices < <(lspci -Dn -d 1f0a:6801 | awk '{ print $1 }')

if (( ${#yt6801_devices[@]} == 0 )); then
  omarchy-pkg-drop yt6801-dkms
  exit 0
fi

for device in "${yt6801_devices[@]}"; do
  if [[ ! $device =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[[:xdigit:]]$ ]]; then
    echo "Invalid YT6801 PCI address: $device" >&2
    exit 1
  fi
done

if ! modinfo -F alias dwmac-motorcomm | grep -Fqx 'pci:v00001F0Ad00006801sv*sd*bc*sc*i*'; then
  echo "The running kernel does not provide YT6801 support in dwmac-motorcomm." >&2
  echo "Reboot into the latest Omarchy kernel and rerun omarchy-migrate." >&2
  exit 1
fi

# Load and validate the replacement before removing the installed fallback.
sudo modprobe dwmac-motorcomm
omarchy-pkg-drop yt6801-dkms

if lsmod | awk '$1 == "yt6801" { found = 1 } END { exit !found }'; then
  sudo modprobe -r yt6801
fi

for device in "${yt6801_devices[@]}"; do
  if ! lspci -Dks "$device" | grep -Eq 'Kernel driver in use: dwmac[-_]motorcomm'; then
    printf '%s\n' "$device" | sudo tee /sys/bus/pci/drivers_probe >/dev/null
  fi
done

for device in "${yt6801_devices[@]}"; do
  if ! lspci -Dks "$device" | grep -Eq 'Kernel driver in use: dwmac[-_]motorcomm'; then
    echo "YT6801 device $device did not bind to dwmac-motorcomm." >&2
    echo "Reboot and rerun omarchy-migrate." >&2
    exit 1
  fi
done
