echo "Allow passwordless intel-lpmd power profile sync"

if pacman -Q intel-lpmd &>/dev/null; then
  sudo tee /etc/sudoers.d/omarchy-intel-lpmd >/dev/null <<EOF
$USER ALL=(root) NOPASSWD: /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_AUTO, /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_FORCE_OFF, /usr/bin/busctl call org.freedesktop.intel_lpmd /org/freedesktop/intel_lpmd org.freedesktop.intel_lpmd LPM_FORCE_ON
EOF
  sudo chmod 440 /etc/sudoers.d/omarchy-intel-lpmd
fi
