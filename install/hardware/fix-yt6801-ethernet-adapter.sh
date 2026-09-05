# Use the upstream driver for the Motorcomm YT6801 adapter used by the Slimbook Executive.
if [[ -n $(lspci -Dn -d 1f0a:6801) ]]; then
  omarchy-pkg-drop yt6801-dkms
fi
