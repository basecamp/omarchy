# Temporarily disable WiFi 7 (EHT/802.11be) on Intel BE200 cards.
# Linux kernel bug 221675 tracks a firmware assertion after warm reconnects
# at 6 GHz/320 MHz. Disabling EHT avoids the failing channel context.
# https://bugzilla.kernel.org/show_bug.cgi?id=221675

if lspci -nn | grep -q '\[8086:272b\]'; then
  sudo tee /etc/modprobe.d/iwlwifi-disable-eht.conf <<'EOF'
# Temporary workaround for Intel BE200 320 MHz firmware assertions
# Remove this file when Linux kernel bug 221675 is fixed
options iwlwifi disable_11be=Y
EOF
fi
