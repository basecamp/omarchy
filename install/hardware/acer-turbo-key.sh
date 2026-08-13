# Acer Predator and Nitro laptops keep the Turbo key, the fan sensors, and the
# full platform_profile range locked until acer_wmi loads with predator_v4=1
# (kernel >= 6.8.6). The option applies whatever GPU the machine carries. Only
# an active options line counts, so a user who commented theirs out keeps that.
if omarchy-hw-acer-predator && modinfo -p acer_wmi 2>/dev/null | grep -q '^predator_v4:'; then
  if ! grep -Eqs '^[[:space:]]*options[[:space:]]+acer_wmi[[:space:]].*predator_v4=1' /etc/modprobe.d/acer-wmi.conf; then
    mkdir -p /etc/modprobe.d
    echo "options acer_wmi predator_v4=1" >>/etc/modprobe.d/acer-wmi.conf
  fi
fi
