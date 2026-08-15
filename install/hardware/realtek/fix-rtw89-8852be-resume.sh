# RTL8852BE firmware/PCI comes back wedged from s2idle — the rtw89 resume
# path fails with DBI / xtal / mac preinit -110, and rfkill/nmcli cannot
# recover it. Install a sleep hook that cold-probes the driver instead.
# Remove when a later kernel can resume this chip.
#
# Buffer lspci before matching. A piped grep can SIGPIPE a chatty lspci
# under pipefail and look like "no such hardware" (#6608).

pci_info=$(lspci -nn)

if [[ $pci_info == *'[10ec:b852]'* ]]; then
  echo "Detected RTL8852BE; installing s2idle Wi-Fi resume hook"

  dest=/usr/lib/systemd/system-sleep/rtw89-8852be
  mkdir -p "$(dirname "$dest")"
  cp -p "$OMARCHY_PATH/default/systemd/system-sleep/rtw89-8852be" "$dest"
  chmod +x "$dest"
fi
