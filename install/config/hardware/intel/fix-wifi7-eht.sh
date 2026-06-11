# Temporary fix for Dell XPS 14/16 on Panther Lake
# Disable WiFi 7 (EHT/802.11be) on Intel BE200/BE211 cards
# The iwlwifi driver has a broken EHT RX data path — APs drop to MCS 0 NSS 1
# when EHT is negotiated, making WiFi unusable. Disabling EHT falls
# back to WiFi 6 (HE/802.11ax) which works at full speed.
# This should be removed when Intel fixes the firmware/driver.

if lspci -nn | grep -qE '\[8086:(e440|272b)\]'; then
  sudo tee /etc/modprobe.d/iwlwifi-disable-eht.conf <<'EOF'
# Temporary fix Dell XPS 14/16 on Panther lake
# Disable WiFi 7 (EHT) on Intel BE200/BE211 — broken RX rate adaptation
# Remove this file when fixes land in the iwlwifi EHT data path
options iwlwifi disable_11be=Y
EOF
fi
