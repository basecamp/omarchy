echo "Install Apple Broadcom Wi-Fi firmware on Macs brcmfmac drives"

dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
pacman_conf="${OMARCHY_BRCMFMAC_PACMAN_CONF:-/etc/pacman.conf}"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! lspci -nn | grep "106b:180[12]" >/dev/null &&
  ! { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43ba|43bb|43bc|43a3|43dc|4464|4488|4425|4433)" >/dev/null; }; then
  exit 0
fi

if ! grep -q '^\[arch-mact2\]' "$pacman_conf"; then
  sudo tee -a "$pacman_conf" >/dev/null <<'EOF'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi

if omarchy-pkg-missing apple-bcm-firmware; then
  sudo pacman -Sy
  omarchy-pkg-add apple-bcm-firmware
  omarchy-state set reboot-required
fi
