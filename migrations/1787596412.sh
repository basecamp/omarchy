echo "Keep RTL8852BE Wi-Fi alive across suspend"

# Only machines carrying the affected Realtek card need any of this. Read lspci
# into a variable rather than piping it into grep -q: grep quits at the first
# match, lspci catches SIGPIPE, and under the runner's pipefail that 141 reads
# as "no such hardware" on the very machines this targets (#6608).
pci_devices=$(lspci -nn)

[[ $pci_devices == *"[10ec:b852]"* ]] || exit 0

conf_source="$OMARCHY_PATH/default/modprobe.d/omarchy-rtw89.conf"
conf=/etc/modprobe.d/omarchy-rtw89.conf
hook_source="$OMARCHY_PATH/default/systemd/system-sleep/rtw89-suspend"
hook=/usr/lib/systemd/system-sleep/rtw89-suspend

# Another user on the same machine may have applied this already.
if ! cmp -s "$conf_source" "$conf"; then
  sudo mkdir -p /etc/modprobe.d
  sudo install -m 644 "$conf_source" "$conf"
fi

if ! cmp -s "$hook_source" "$hook"; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo install -m 755 "$hook_source" "$hook"
fi
