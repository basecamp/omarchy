echo "Install the missing NVRAM for Broadcom BCM43602 Wi-Fi on Apple Macs"

# The install-time leaf only reaches machines set up after it shipped, so an
# existing install on a 2015-2017 Mac still has no NVRAM for its BCM43602:
# 2.4GHz-only scans, crippled signal, and WPA handshakes that time out. See
# install/hardware/apple/fix-brcmfmac-nvram.sh for the failure this fixes and
# for why the gate is limited to 14e4:43ba/43bb/43bc.
dmi_vendor="${OMARCHY_BRCMFMAC_NVRAM_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
pci_devices="${OMARCHY_BRCMFMAC_NVRAM_PCI_DEVICES:-/sys/bus/pci/devices}"
dest="${OMARCHY_BRCMFMAC_NVRAM_DEST:-/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt}"
src="${OMARCHY_BRCMFMAC_NVRAM_SRC:-$OMARCHY_PATH/default/firmware/apple/brcmfmac43602-pcie.txt}"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! [[ $sys_vendor == Apple* ]] ||
  ! lspci -nn | grep -E "14e4:(43ba|43bb|43bc)" >/dev/null; then
  exit 0
fi

# A file already there wins: user-placed or package-shipped, both outrank this
# copy. The same check keeps the migration idempotent for the next user on a
# machine already repaired.
if [[ -e $dest ]]; then
  exit 0
fi

# Substitute the NIC's live MAC for the donor board's placeholder, the same way
# the install-time leaf does. awk reads the whole lspci stream instead of
# exiting on the first match, so the pipe stays safe under pipefail (#6608).
bdf="$(lspci -Dnn | awk '/14e4:(43ba|43bb|43bc)/ { if (!found) { print $1; found=1 } }')"
mac=""
if [[ -n $bdf ]]; then
  net_addrs=("$pci_devices/$bdf"/net/*/address)
  mac="$(cat "${net_addrs[0]}" 2>/dev/null || true)"
fi

work="$(mktemp)"
if [[ -n $mac ]]; then
  sed "s/^macaddr=.*/macaddr=$mac/" "$src" >"$work"
else
  # No MAC discoverable: drop the line and let the firmware use the OTP
  # address, which is how these NICs already run with no NVRAM at all.
  sed '/^macaddr=/d' "$src" >"$work"
fi

sudo install -Dm644 "$work" "$dest"
rm -f "$work"

# brcmfmac reads the NVRAM when the module loads. Reloading it here would drop
# the user's live Wi-Fi connection, possibly the one carrying this update.
omarchy-state set reboot-required
