# Realtek RTL8852BE (10ec:b852) does not survive suspend: the Wi-Fi interface is
# simply gone after a lid close, with nothing in dmesg to explain it.
#
# Its PCIe root port drops to D3cold during s2idle, which turns off the ACPI
# power resource under _PR3 that gates power to the slot, so the card resumes
# unpowered and is never re-enumerated. Two files fix it: modprobe options that
# keep ASPM L1/L1SS and CLKREQ# off the link, and a sleep hook that holds the
# port out of D3cold and cycles the card off and back onto the bus.
#
# Verified on an ASUS TUF Gaming F16 (FX607VJ, Intel root port 8086:51bf).

# Read lspci into a variable rather than piping it into grep -q: grep quits at
# the first match, lspci catches SIGPIPE, and under the caller's pipefail that
# 141 reads as "no such hardware" on the very machines this targets (#6608).
pci_devices=$(lspci -nn)

if [[ $pci_devices == *"[10ec:b852]"* ]]; then
  mkdir -p /etc/modprobe.d
  install -m 644 "$OMARCHY_PATH/default/modprobe.d/omarchy-rtw89.conf" \
    /etc/modprobe.d/omarchy-rtw89.conf

  mkdir -p /usr/lib/systemd/system-sleep
  install -m 755 "$OMARCHY_PATH/default/systemd/system-sleep/rtw89-suspend" \
    /usr/lib/systemd/system-sleep/rtw89-suspend
fi
