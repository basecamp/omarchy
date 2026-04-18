# Install Intel Low Power Mode Daemon for supported hybrid Intel CPUs (Alder Lake and newer)
# Supported models: Alder Lake (151/154), Raptor Lake (183/186/191),
# Meteor Lake (170/172), Lunar Lake (189), Panther Lake (204)

if omarchy-hw-intel && omarchy-battery-present; then
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  if [[ "$cpu_model" =~ ^(151|154|170|172|183|186|189|191|204)$ ]]; then
    omarchy-pkg-add intel-lpmd
    sudo systemctl enable intel_lpmd.service
    sudo tee /etc/sudoers.d/omarchy-intel-lpmd >/dev/null <<EOF
$USER ALL=(root) NOPASSWD: /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_AUTO, /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_FORCE_OFF, /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_FORCE_ON
EOF
    sudo chmod 440 /etc/sudoers.d/omarchy-intel-lpmd
  fi
fi
