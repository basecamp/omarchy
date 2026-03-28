omarchy-hw-amd-isp4 || exit 0

# Install AMD ISP4 camera driver and fix modules failing to resume from sleep.
# Affects laptops with RYZEN AI MAX+ and ISP4 webcams (e.g. HP ZBook Ultra G1a).

KERNEL_HEADERS="$(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' | head -1)-headers"

omarchy-pkg-add "$KERNEL_HEADERS"
omarchy-pkg-aur-add amdisp4-dkms

# The ISP4 modules need to be unloaded before suspend and reloaded in order after resume.
sudo mkdir -p /usr/lib/systemd/system-sleep
sudo mkdir -p /usr/lib/systemd/system-sleep
sudo install -m 0755 -o root -g root \
  "$OMARCHY_PATH/default/systemd/system-sleep/omarchy-isp-suspend" \
  /usr/lib/systemd/system-sleep/omarchy-isp-suspend
