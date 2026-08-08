# Apple Macs ship Broadcom Wi-Fi driven by brcmfmac, whose firmware runs the WPA
# handshake itself. On these parts that offload fails against an access point in
# WPA2/WPA3 transition mode: the client associates, the four-way handshake never
# completes, and NetworkManager reports the password as wrong.
#
# feature_disable turns off the firmware supplicant (FWSUP, 0x2000) and firmware
# authenticator (FWAUTH, 0x80000), handing the handshake back to wpa_supplicant
# in software.
#
# This quirk already shipped for T2 Macs. The bug is in the Broadcom firmware,
# not in the T2 bridge, so Macs without one need it just as much: a
# MacBookPro11,4 with BCM43602 (14e4:43ba) and 2015 firmware fails exactly this
# way, and connects once the offload is disabled.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if [[ $sys_vendor == "Apple Inc." || $sys_vendor == "Apple Computer, Inc." ]] &&
   lspci -nn | grep -qiE 'network controller.*\[14e4:'; then
  echo "Detected a Mac with Broadcom Wi-Fi; running the WPA handshake in software"

  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/brcmfmac.conf <<'EOF'
# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000
EOF
fi
