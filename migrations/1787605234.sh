echo "Fix T2 Mac Wi-Fi suspend by unloading brcmfmac before sleep"

# The install-time hook only reaches machines set up after it shipped, so an
# existing T2 install still hits the brcmfmac PCIe D3 timeout on every
# suspend attempt and never actually sleeps: it stays awake in a suspend/
# resume loop that looks like hibernation from the lid but drains the
# battery. See install/hardware/apple/fix-brcmfmac-suspend.sh for the
# failure this fixes.
hook="${OMARCHY_T2_WIFI_SUSPEND_HOOK:-/usr/lib/systemd/system-sleep/t2-wifi-suspend}"
source_hook="${OMARCHY_T2_WIFI_SUSPEND_SOURCE:-$OMARCHY_PATH/default/systemd/system-sleep/t2-wifi-suspend}"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

if [[ -f $hook ]] && cmp -s "$source_hook" "$hook"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$hook")"
sudo cp -p "$source_hook" "$hook"
