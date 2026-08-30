echo "Keep T2 Mac USB-C ports awake after suspend"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

rule="${OMARCHY_T2_USBC_RULE:-/etc/udev/rules.d/99-omarchy-t2-usbc-hotplug.rules}"

if [[ -f $rule ]]; then
  exit 0
fi

# The Titan Ridge USB-C host controllers lose power in deep sleep and, once
# reinitialized on resume, no longer wake on hot-plug from runtime suspend.
# Holding them on keeps the ports usable after every sleep.
sudo install -Dm644 "$OMARCHY_PATH/default/udev/t2-usbc-hotplug.rules" "$rule"
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=pci \
  --attr-match=vendor=0x8086 --attr-match=device=0x15ec
