omarchy-hw-amd-isp4 || exit 0

# Install AMD ISP4 camera driver and fix modules failing to resume from sleep.
# Affects laptops with RYZEN AI MAX+ and ISP4 webcams (e.g. HP ZBook Ultra G1a).

omarchy-pkg-add linux-headers
omarchy-pkg-aur-add amdisp4-dkms

# The ISP4 modules need to be unloaded before suspend and reloaded in order after resume.
sudo tee /usr/lib/systemd/system-sleep/omarchy-isp-suspend >/dev/null <<'EOF'
#!/bin/bash

MODULES="amd_isp4_capture i2c_designware_amdisp pinctrl_amdisp amd_isp4"

case $1 in
  pre)
    modprobe -rq $MODULES 2>/dev/null || true
    ;;
  post)
    for mod in $MODULES; do
      modprobe -q $mod 2>/dev/null || true
    done
    ;;
esac
EOF

sudo chmod +x /usr/lib/systemd/system-sleep/omarchy-isp-suspend
