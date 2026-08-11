# Apple Macs ship Broadcom Wi-Fi driven by brcmfmac, whose firmware runs the WPA
# handshake itself. On these parts that offload fails against an access point in
# WPA2/WPA3 transition mode: the client associates, the four-way handshake never
# completes, and NetworkManager reports the password as wrong.
#
# feature_disable turns off the firmware supplicant (FWSUP, 0x2000) and firmware
# authenticator (FWAUTH, 0x80000), handing the handshake back to wpa_supplicant
# in software.
#
# This quirk already shipped for T2 Macs, detected by the T2 PCI ID that every
# one of them carries. The bug is in the Broadcom firmware, not in the T2 bridge,
# so every Mac whose Wi-Fi brcmfmac drives needs it: a MacBookPro11,4 with
# BCM43602 and 2015 firmware fails exactly this way, and connects once the
# offload is disabled.
#
# The IDs are brcmfmac's own, from brcm_hw_ids.h: BCM43602 and its single-band
# variants in 2015-2017 Macs, BCM4350, BCM4355 and BCM4364 in the 2018-2019
# machines including the T2-less iMac19,1 and iMac19,2, and BCM4377/4378/4387
# from the T2 era on. The BCM4360 in 2013-2015 Macs is deliberately absent: it
# runs the out-of-tree wl driver, which never reads a brcmfmac option.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if lspci -nn | grep "106b:180[12]" >/dev/null ||
  { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43ba|43bb|43bc|43a3|43dc|4464|4488|4425|4433)" >/dev/null; }; then
  echo "Detected a Mac with Broadcom Wi-Fi; running the WPA handshake in software"

  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/brcmfmac.conf <<'EOF'
# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000
EOF
fi
