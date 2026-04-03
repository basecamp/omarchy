echo "Install nuphyctl-bin on systems with a NuPhy keyboard"

if omarchy-hw-nuphyio-keyboard && omarchy-pkg-missing nuphyctl-bin; then
  omarchy-pkg-aur-add nuphyctl-bin
fi
