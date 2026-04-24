# Unlock the Turbo key, fan sensors, and full platform_profile range
# on Acer Predator and Nitro laptops by enabling the acer_wmi
# predator_v4 module option. GPU-agnostic — applies to both
# Intel/NVIDIA and AMD configurations. Requires kernel >= 6.8.6.

if omarchy-hw-acer-predator; then
  MODPROBE_CONF=/etc/modprobe.d/acer-wmi.conf
  if ! grep -qs "predator_v4=1" "$MODPROBE_CONF" 2>/dev/null; then
    echo "options acer_wmi predator_v4=1" | sudo tee "$MODPROBE_CONF" >/dev/null
  fi
fi
