echo "Stop NetworkManager probing the internal T2 NCM interface"

udev_rule="${OMARCHY_T2_NCM_UDEV_RULE:-/etc/udev/rules.d/99-network-t2-ncm.rules}"
nm_conf="${OMARCHY_T2_NCM_NM_CONF:-/etc/NetworkManager/conf.d/99-network-t2-ncm.conf}"

lspci -nn | grep "106b:180[12]" >/dev/null || exit 0

if [[ -f $udev_rule && -f $nm_conf ]] &&
  grep -Fqx 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8233", NAME="t2_ncm"' "$udev_rule" &&
  grep -Fqx '[device-t2-ncm]' "$nm_conf" &&
  grep -Fqx 'match-device=interface-name:t2_ncm' "$nm_conf" &&
  grep -Fqx 'managed=0' "$nm_conf"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$udev_rule")" "$(dirname "$nm_conf")"
printf '%s\n' 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8233", NAME="t2_ncm"' |
  sudo tee "$udev_rule" >/dev/null
printf '%s\n' '[device-t2-ncm]' 'match-device=interface-name:t2_ncm' 'managed=0' |
  sudo tee "$nm_conf" >/dev/null

omarchy-state set reboot-required
