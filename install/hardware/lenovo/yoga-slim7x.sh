# Lenovo Yoga Slim 7x (14Q8X9 / 83ED) board-specific setup.

yoga_slim7x_compatible=""
if [[ -r /sys/firmware/devicetree/base/compatible ]]; then
  yoga_slim7x_compatible=$(tr '\0' '\n' </sys/firmware/devicetree/base/compatible)
fi

if omarchy-hw-qualcomm-soc &&
  { grep -qi '^lenovo,yoga-slim7x$' <<<"$yoga_slim7x_compatible" ||
    omarchy-hw-match 'Yoga Slim 7x' || omarchy-hw-match '83ED'; }; then
  echo "Detected Lenovo Yoga Slim 7x, applying board-specific support..."

  # The Yoga exposes its CPU performance domains through SCMI.
  mkdir -p /etc/modules-load.d
  echo "scmi-cpufreq" >/etc/modules-load.d/yoga-slim7x.conf

  # Its internal keyboard and touchpad are HID-over-I2C. Keep their OF
  # transport in the initramfs so encrypted installs can accept a passphrase.
  mkdir -p /etc/mkinitcpio.conf.d
  cat >/etc/mkinitcpio.conf.d/yoga-slim7x-initramfs.conf <<'CONF'
MODULES+=(i2c-hid-of)
CONF

  # Start the board's DSP remote processors after udev exposes them.
  cat >/etc/systemd/system/yoga-slim7x-remoteprocs.service <<'UNIT'
[Unit]
Description=Start the Lenovo Yoga Slim 7x DSPs
Wants=systemd-udev-settle.service
After=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/share/omarchy/install/hardware/lenovo/start-yoga-slim7x-remoteprocs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl enable yoga-slim7x-remoteprocs.service
fi
