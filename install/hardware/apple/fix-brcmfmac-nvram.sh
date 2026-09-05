# 2015-2017 Apple Macs ship the Broadcom BCM43602, which brcmfmac drives. The
# linux-firmware package provides only the .bin for this part and no NVRAM, and
# without one the firmware's country-code detection never completes (kernel bug
# 193121): scans come back 2.4GHz-only at a fraction of the real signal, and
# the WPA four-way handshake times out, which NetworkManager reports as a
# rejected password. Shipping the board's NVRAM with ccode=0/regrev=1 pins the
# "world" regulatory domain around the broken detection and lets the handshake
# complete. This pairs with fix-brcmfmac-supplicant.sh, which fixes a different
# firmware defect on the same machines; neither replaces the other.
#
# The gate is deliberately narrower than the supplicant quirk's: the NVRAM
# holds this board's calibration data, so it only applies to the BCM43602
# family -- 14e4:43ba/43bb/43bc, the IDs brcmfmac's brcm_hw_ids.h lists for
# BCM43602 and its single-band variants. BCM4360 (14e4:43a0) runs the
# out-of-tree wl driver, which never reads brcmfmac NVRAM, and is excluded.
#
# A file already at the destination wins: user-placed or shipped by a future
# linux-firmware, both outrank this copy, and the skip is silent because it is
# the common case on reruns.
#
# The asset lives under default/, a sibling of the install tree, so it resolves
# from $OMARCHY_PATH (exported by the install entry point and always present at
# runtime) rather than from $OMARCHY_INSTALL, which points at install/ itself.
dest=/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if [[ ! -e $dest ]] && [[ $sys_vendor == Apple* ]] &&
  lspci -nn | grep -E "14e4:(43ba|43bb|43bc)" >/dev/null; then
  echo "Detected a Mac with BCM43602 Wi-Fi; installing its missing NVRAM"

  # The NVRAM's macaddr= line carries the donor board's address, so substitute
  # this NIC's own, found under the matching PCI device. lspci -D prints the
  # domain form /sys uses. awk reads the whole stream instead of exiting on the
  # first match, so the pipe stays safe under pipefail (#6608).
  bdf="$(lspci -Dnn | awk '/14e4:(43ba|43bb|43bc)/ { if (!found) { print $1; found=1 } }')"
  mac=""
  if [[ -n $bdf ]]; then
    net_addrs=(/sys/bus/pci/devices/"$bdf"/net/*/address)
    mac="$(cat "${net_addrs[0]}" 2>/dev/null || true)"
  fi

  work="$(mktemp)"
  if [[ -n $mac ]]; then
    sed "s/^macaddr=.*/macaddr=$mac/" \
      "$OMARCHY_PATH/default/firmware/apple/brcmfmac43602-pcie.txt" >"$work"
  else
    # No MAC discoverable: drop the line entirely and let the firmware fall
    # back to the OTP address, which is how these NICs already run with no
    # NVRAM at all.
    sed '/^macaddr=/d' \
      "$OMARCHY_PATH/default/firmware/apple/brcmfmac43602-pcie.txt" >"$work"
  fi

  install -Dm644 "$work" "$dest"
  rm -f "$work"
fi
