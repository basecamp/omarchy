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
# override path or the packaged path when this runs wins, user-placed or
# package-shipped. Once this copy is installed the override path is searched
# first, so a board file linux-firmware ships later does not replace it.

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

# Arch compresses everything under /usr/lib/firmware, so a packaged board file
# arrives as brcmfmac43602-pcie.<dmi>.txt.zst, not under the name the driver
# asks for. Checking only the plain name would miss it and shadow it anyway.
brcmfmac43602_installed() {
  local name dir suffix
  name=$(brcmfmac43602_dmi_name)
  for dir in "$(brcmfmac43602_fwdir)" "$(brcmfmac43602_packaged_fwdir)"; do
    for suffix in "" .zst .xz; do
      [[ -e $dir/brcmfmac43602-pcie.txt$suffix ]] && return 0
      [[ -n $name && -e "$dir/$name$suffix" ]] && return 0
    done
  done
  return 1
}

# The NIC bound to 14e4:43ba, not the first wireless interface in glob order
# (a USB adapter at install time would otherwise donate its address). The
# wiphy's macaddress is the permanent address; net/*/address is whatever is
# current, which NetworkManager randomises while scanning. 00:90:4c is the
# Broadcom OUI the firmware falls back to when the card has no usable OTP
# address, so it is a placeholder and never worth persisting.
brcmfmac43602_wifi_mac() {
  local bdf pci_devices candidate mac
  pci_devices=$(brcmfmac43602_pci_devices)
  bdf=$(lspci -Dnn | awk '/14e4:43ba/ { if (!found) { print $1; found=1 } }')
  [[ -n $bdf ]] || return 1
  for candidate in "$pci_devices/$bdf"/ieee80211/phy*/macaddress "$pci_devices/$bdf"/net/*/address; do
    mac=$(cat "$candidate" 2>/dev/null || true)
    [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] || continue
    if [[ ${mac,,} == 00:90:4c:* ]]; then
      return 1
    fi
    printf '%s\n' "$mac"
    return 0
  done
  return 1
}

# Reloading brcmfmac here would drop a live Wi-Fi connection, including the
# one carrying an update. Callers must not wrap this in `if`; bash would then
# disable errexit for the body and a failed install would look like success.
#
# Both names are staged under temporary names and renamed into place together.
# A write that fails part-way (ENOSPC truncates its destination) must not leave
# a partial file under the name the driver loads, where brcmfmac43602_installed
# would keep it forever and the migration would never ask for the reboot.
brcmfmac43602_install() {
  local src fwdir mac work name target
  local -a targets

  src=$(brcmfmac43602_nvram_src)
  [[ -f $src ]] || return 1

  fwdir=$(brcmfmac43602_fwdir)
  targets=("$fwdir/brcmfmac43602-pcie.txt")
  name=$(brcmfmac43602_dmi_name)
  if [[ -n $name ]]; then
    targets+=("$fwdir/$name")
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
  for target in "${targets[@]}"; do
    if ! brcmfmac43602_as_root install -m 644 "$work" "$target.tmp"; then
      brcmfmac43602_as_root rm -f "${targets[@]/%/.tmp}"
      rm -f "$work"
      return 1
    fi
  done
  rm -f "$work"
  for target in "${targets[@]}"; do
    if ! brcmfmac43602_as_root mv -f "$target.tmp" "$target"; then
      brcmfmac43602_as_root rm -f "${targets[@]}" "${targets[@]/%/.tmp}"
      return 1
    fi
  done
}
