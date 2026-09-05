# GPD Pocket 4 (G1628-04): the 8.8" panel is physically portrait-mounted and
# used landscape, so orientation has to be fixed at three layers:
#   - boot: Limine menu rotation plus kernel params for the text console
#     (fbcon, LUKS prompt) and DRM-based renderers (plymouth)
#   - libinput: calibration matrix for the NVTK0603 digitizer frame
#   - session: omarchy-gpd-pocket-4-rotate.service tracks the accelerometer
#     and keeps monitor + touch transforms in sync (the DRM panel-orientation
#     property is ignored by Hyprland, so there is no double rotation)
if omarchy-hw-gpd-pocket-4; then
  omarchy-pkg-add iio-sensor-proxy

  mkdir -p /etc/limine-entry-tool.d
  cat > /etc/limine-entry-tool.d/gpd-pocket4-orientation.conf <<'EOF'
# GPD Pocket 4: portrait panel mounted landscape. fbcon=rotate:1 (90 degrees
# clockwise) fixes the text console and LUKS prompt; panel_orientation covers
# DRM-based renderers.
KERNEL_CMDLINE[default]+=" fbcon=rotate:1 video=eDP-1:panel_orientation=right_side_up"
EOF

  # Limine's graphical menu is rotated with a global option that
  # limine-entry-tool does not manage; it preserves unmanaged options across
  # regenerations, so a one-time prepend is enough.
  if [[ -e /boot/limine.conf ]] && ! grep -q "^interface_rotation:" /boot/limine.conf; then
    sed -i "1i interface_rotation: 90" /boot/limine.conf
  fi

  # Rotate the raw digitizer frame into display orientation (270 degrees
  # clockwise; matrix reference in the libinput docs).
  mkdir -p /etc/udev/rules.d
  cat > /etc/udev/rules.d/99-gpd-pocket4-touchscreen.rules <<'EOF'
# GPD Pocket 4 (G1628-04) NVTK0603 touchscreen
# Calibrate touch input for the 270-degree rotated portrait panel.
# Matrix reference (libinput docs): "0 1 0 -1 0 1" == 270 degrees clockwise.
ACTION=="add|change", KERNEL=="event[0-9]*", ATTRS{name}=="NVTK0603:00 0603:F001", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
EOF
  udevadm control --reload
fi
