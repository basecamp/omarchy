echo "Add Intel IPU6 MIPI camera support for Tiger/Alder/Raptor Lake"

if lspci | grep -qi "Intel Corporation.*IPU" && \
   ! grep -q "OVTI08F4" /sys/bus/acpi/devices/*/hid 2>/dev/null; then

  if omarchy-pkg-missing libcamera-ipu6; then
    omarchy-pkg-aur-add intel-ipu6-camera-hal-git libcamera-ipu6 libcamera-ipu6-ipa gst-plugin-libcamera-ipu6
    omarchy-pkg-add pipewire-libcamera
  fi

  sudo usermod -aG video "${USER}"

  mkdir -p ~/.config/systemd/user/wireplumber.service.d
  cat > ~/.config/systemd/user/wireplumber.service.d/20-ipu6-camera.conf << 'EOF'
[Service]
Environment=__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
Environment=LIBCAMERA_SOFTISP_MODE=cpu
Environment=LIBCAMERA_PIPELINES_MATCH_LIST=simple,uvcvideo
EOF

  mkdir -p ~/.config/systemd/user/xdg-desktop-portal.service.d
  cat > ~/.config/systemd/user/xdg-desktop-portal.service.d/10-pipewire-restart.conf << 'EOF'
[Unit]
BindsTo=pipewire.service
After=pipewire.service
EOF

  systemctl --user daemon-reload

  sudo mkdir -p /usr/share/libcamera/ipa/simple
  if [ ! -f /usr/share/libcamera/ipa/simple/ov02c10.yaml ]; then
    sudo tee /usr/share/libcamera/ipa/simple/ov02c10.yaml > /dev/null << 'EOF'
# SPDX-License-Identifier: CC0-1.0
# Minimal tuning for OmniVision OV02C10 (2MP, 1928x1092, SGRBG10).
# No upstream calibration data exists yet — based on ov01a10 (same family).
# AWB works in normal lighting; degrades in very dark rooms (known upstream limitation).
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
      black: 16
  - Awb:
  - Adjust:
  - Agc:
...
EOF
  fi

fi

# Enable PipeWire camera portal for Chromium (benefits all PipeWire users, not IPU6-specific)
omarchy-refresh-chromium
