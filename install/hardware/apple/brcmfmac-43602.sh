# Shared BCM43602 5 GHz NVRAM helpers for the install leaf and the migration.
#
# linux-firmware-broadcom ships the BCM43602 chip firmware but not a board
# calibration file. Without one, brcmfmac brings the card up with placeholder
# 5 GHz values (aa5g=1, no per-channel tx-power tables) and only 2.4 GHz
# networks are visible.
#
# The NVRAM is a community dump (kernel.org bugzilla attachment 290569) with
# ccode=00 / regrev=245, which defers channel legality to the host. Omarchy
# already persists that from the timezone via set-wireless-regdom.sh. It is
# calibration for one board, not every Apple BCM43602: this only runs on the
# 2017 Touch Bar MacBook Pros (MacBookPro14,2 / 14,3) where the dump has been
# seen to work. MacBookPro13,3 is the same PCI ID and is excluded — a report
# of this dump on that model described unusable range.
#
# Destinations live under /usr/lib/firmware/updates so they override, and do
# not collide with, linux-firmware-broadcom. A file already at either the
# override path or the packaged path wins: user-placed or a future
# linux-firmware board file both outrank this copy.

brcmfmac43602_as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

brcmfmac43602_fwdir() {
  printf '%s\n' "${OMARCHY_BRCMFMAC_FWDIR:-/usr/lib/firmware/updates/brcm}"
}

brcmfmac43602_packaged_fwdir() {
  printf '%s\n' "${OMARCHY_BRCMFMAC_PACKAGED_FWDIR:-/usr/lib/firmware/brcm}"
}

brcmfmac43602_nvram_src() {
  printf '%s\n' "${OMARCHY_BRCMFMAC43602_NVRAM:-${OMARCHY_PATH:-/usr/share/omarchy}/default/firmware/apple/brcmfmac43602-pcie.txt}"
}

brcmfmac43602_dmi_vendor() {
  cat "${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}" 2>/dev/null || true
}

brcmfmac43602_dmi_product() {
  cat "${OMARCHY_BRCMFMAC_DMI_PRODUCT:-/sys/class/dmi/id/product_name}" 2>/dev/null || true
}

brcmfmac43602_pci_devices() {
  printf '%s\n' "${OMARCHY_BRCMFMAC_PCI_DEVICES:-/sys/bus/pci/devices}"
}

# Dual-band BCM43602 (14e4:43ba) on the 2017 Touch Bar MacBook Pros. The 2 GHz
# only (43bb) and 5 GHz-only (43bc) variants are left alone, as are T2-era
# chips that already get board files from apple-bcm-firmware.
brcmfmac43602_needed() {
  local sys_vendor product
  sys_vendor=$(brcmfmac43602_dmi_vendor)
  product=$(brcmfmac43602_dmi_product)
  [[ $sys_vendor == Apple* ]] || return 1
  [[ $product =~ ^MacBookPro14,[23]$ ]] || return 1
  lspci -nn | grep "14e4:43ba" >/dev/null
}

brcmfmac43602_dmi_name() {
  local vendor product
  vendor=$(brcmfmac43602_dmi_vendor)
  product=$(brcmfmac43602_dmi_product)
  [[ -n $vendor && -n $product ]] || return 0
  printf '%s\n' "brcmfmac43602-pcie.${vendor}-${product}.txt"
}

brcmfmac43602_installed() {
  local name dir
  for dir in "$(brcmfmac43602_fwdir)" "$(brcmfmac43602_packaged_fwdir)"; do
    [[ -e $dir/brcmfmac43602-pcie.txt ]] && return 0
    name=$(brcmfmac43602_dmi_name)
    [[ -n $name && -e "$dir/$name" ]] && return 0
  done
  return 1
}

# The NIC bound to 14e4:43ba, not the first wireless interface in glob order
# (a USB adapter at install time would otherwise donate its address).
brcmfmac43602_wifi_mac() {
  local bdf pci_devices net_addrs mac
  pci_devices=$(brcmfmac43602_pci_devices)
  bdf=$(lspci -Dnn | awk '/14e4:43ba/ { if (!found) { print $1; found=1 } }')
  [[ -n $bdf ]] || return 1
  net_addrs=("$pci_devices/$bdf"/net/*/address)
  mac=$(cat "${net_addrs[0]}" 2>/dev/null || true)
  if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    printf '%s\n' "$mac"
    return 0
  fi
  return 1
}

# Reloading brcmfmac here would drop a live Wi-Fi connection, including the
# one carrying an update. Callers must not wrap this in `if`; bash would then
# disable errexit for the body and a failed install would look like success.
brcmfmac43602_install() {
  local src fwdir generic dmi mac work name

  src=$(brcmfmac43602_nvram_src)
  [[ -f $src ]] || return 1

  fwdir=$(brcmfmac43602_fwdir)
  generic="$fwdir/brcmfmac43602-pcie.txt"
  dmi=""
  name=$(brcmfmac43602_dmi_name)
  if [[ -n $name ]]; then
    dmi="$fwdir/$name"
  fi

  work=$(mktemp) || return 1
  if mac=$(brcmfmac43602_wifi_mac); then
    if ! sed "s/^macaddr=.*/macaddr=$mac/" "$src" >"$work"; then
      rm -f "$work"
      return 1
    fi
  else
    # No MAC discoverable: drop the line and let the firmware use the OTP
    # address, which is how these NICs already run with no NVRAM at all.
    if ! sed '/^macaddr=/d' "$src" >"$work"; then
      rm -f "$work"
      return 1
    fi
  fi

  if ! brcmfmac43602_as_root mkdir -p "$fwdir"; then
    rm -f "$work"
    return 1
  fi
  if ! brcmfmac43602_as_root install -m 644 "$work" "$generic"; then
    rm -f "$work"
    return 1
  fi
  if [[ -n $dmi ]]; then
    if ! brcmfmac43602_as_root install -m 644 "$work" "$dmi"; then
      rm -f "$work"
      return 1
    fi
  fi
  rm -f "$work"
}
