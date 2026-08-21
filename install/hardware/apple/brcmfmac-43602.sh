# Shared BCM43602 5 GHz NVRAM helpers for the install leaf and the migration.
#
# linux-firmware-broadcom ships the BCM43602 chip firmware but not a board
# calibration file. Without one, brcmfmac brings the card up with placeholder
# 5 GHz values (aa5g=1, no per-channel tx-power tables) and only 2.4 GHz
# networks are visible. A calibrated NVRAM with aa5g=7 / txchain=7 / rxchain=7
# and ccode=00 / regrev=245 (defer channel legality to the host) unlocks 5 GHz.
#
# The NVRAM is a community dump attached to a BCM43602 kernel.org bugzilla
# ticket (attachment 290569), not vendor-certified. Channel legality still
# follows the host regulatory domain; Omarchy already persists that from the
# timezone via install/hardware/set-wireless-regdom.sh.
#
# Destinations live under /usr/lib/firmware/updates so they override, and do
# not collide with, linux-firmware-broadcom.

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

brcmfmac43602_nvram_src() {
  printf '%s\n' "${OMARCHY_BRCMFMAC43602_NVRAM:-${OMARCHY_INSTALL:-${OMARCHY_PATH:-/usr/share/omarchy}/install}/hardware/apple/brcmfmac43602-pcie.txt}"
}

brcmfmac43602_dmi_vendor() {
  cat "${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}" 2>/dev/null || true
}

brcmfmac43602_dmi_product() {
  cat "${OMARCHY_BRCMFMAC_DMI_PRODUCT:-/sys/class/dmi/id/product_name}" 2>/dev/null || true
}

# Dual-band BCM43602 (14e4:43ba) on Apple hardware. The 2 GHz-only (43bb) and
# 5 GHz-only (43bc) variants are left alone, as are T2-era chips that already
# get board files from apple-bcm-firmware.
brcmfmac43602_needed() {
  local sys_vendor
  sys_vendor=$(brcmfmac43602_dmi_vendor)
  [[ $sys_vendor == Apple* ]] || return 1
  lspci -nn | grep "14e4:43ba" >/dev/null
}

brcmfmac43602_file_complete() {
  local file=$1
  [[ -f $file ]] || return 1
  grep -qx 'aa5g=7' "$file" || return 1
  grep -qx 'txchain=7' "$file" || return 1
  grep -qx 'ccode=00' "$file" || return 1
}

brcmfmac43602_dmi_dest() {
  local fwdir vendor product
  fwdir=$(brcmfmac43602_fwdir)
  vendor=$(brcmfmac43602_dmi_vendor)
  product=$(brcmfmac43602_dmi_product)
  [[ -n $vendor && -n $product ]] || return 0
  printf '%s\n' "$fwdir/brcmfmac43602-pcie.${vendor}-${product}.txt"
}

brcmfmac43602_complete() {
  local fwdir generic dmi
  fwdir=$(brcmfmac43602_fwdir)
  generic="$fwdir/brcmfmac43602-pcie.txt"
  brcmfmac43602_file_complete "$generic" || return 1
  dmi=$(brcmfmac43602_dmi_dest)
  [[ -z $dmi ]] && return 0
  brcmfmac43602_file_complete "$dmi"
}

brcmfmac43602_wifi_mac() {
  local netdir wireless iface mac nullglob_was_on=0
  netdir="${OMARCHY_BRCMFMAC_NETDIR:-/sys/class/net}"
  shopt -q nullglob && nullglob_was_on=1
  shopt -s nullglob
  for wireless in "$netdir"/*/wireless; do
    iface=$(basename "$(dirname "$wireless")")
    mac=$(cat "$netdir/$iface/address" 2>/dev/null || true)
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
      (( nullglob_was_on )) || shopt -u nullglob
      printf '%s\n' "$mac"
      return 0
    fi
  done
  (( nullglob_was_on )) || shopt -u nullglob
  return 1
}

# Installs the calibrated NVRAM. Returns 0 when files were written, 1 when this
# machine does not need it or already has a complete copy. Reloading brcmfmac
# here would drop a live Wi-Fi connection, including the one carrying an update.
brcmfmac43602_apply() {
  local src fwdir generic dmi mac

  brcmfmac43602_needed || return 1
  brcmfmac43602_complete && return 1

  src=$(brcmfmac43602_nvram_src)
  [[ -f $src ]] || return 1

  fwdir=$(brcmfmac43602_fwdir)
  generic="$fwdir/brcmfmac43602-pcie.txt"
  dmi=$(brcmfmac43602_dmi_dest)

  brcmfmac43602_as_root mkdir -p "$fwdir"
  brcmfmac43602_as_root install -m 644 "$src" "$generic"
  if [[ -n $dmi ]]; then
    brcmfmac43602_as_root install -m 644 "$src" "$dmi"
  fi

  if mac=$(brcmfmac43602_wifi_mac); then
    brcmfmac43602_as_root sed -i "s/^macaddr=.*/macaddr=$mac/" "$generic"
    if [[ -n $dmi ]]; then
      brcmfmac43602_as_root sed -i "s/^macaddr=.*/macaddr=$mac/" "$dmi"
    fi
  fi

  return 0
}
