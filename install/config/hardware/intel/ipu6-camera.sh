# Install MIPI camera support for Intel IPU6 hardware (Tiger Lake / Alder Lake / Raptor Lake)
# Uses the libcamera fork with the out-of-tree IPU6 pipeline handler.
#
# Several workarounds are required beyond just installing packages:
#   - LIBCAMERA_SOFTISP_MODE=cpu: GPU (EGL) debayering produces DMA-BUF with wrong
#     stride that Chromium rejects with EINVAL. CPU debayering produces system memory
#     buffers with compact stride that work across sandbox boundaries.
#   - LIBCAMERA_PIPELINES_MATCH_LIST: skips the broken ipu6 HAL, uses SoftwareISP.
#   - __EGL_VENDOR_LIBRARY_FILENAMES: forces Mesa EGL on hybrid GPU systems to
#     prevent cross-device DMA-BUF crash in libgallium.
#   - video group: required to open /dev/dri/renderD128 for Mesa EGL.
#   - xdg-desktop-portal BindsTo pipewire: prevents portal losing camera connection
#     on wireplumber restart.
#   - ov02c10.yaml: minimal sensor calibration; libcamera falls back to uncalibrated
#     without it (no upstream calibration for this sensor yet).

if lspci | grep -qi "Intel Corporation.*IPU" && \
   ! grep -q "OVTI08F4" /sys/bus/acpi/devices/*/hid 2>/dev/null; then

  omarchy-pkg-aur-add intel-ipu6-camera-hal-git libcamera-ipu6 libcamera-ipu6-ipa gst-plugin-libcamera-ipu6
  omarchy-pkg-add pipewire-libcamera

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
