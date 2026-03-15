# Enable thermald for Intel laptops (Sandy Bridge and newer)
# Thermald is useful for Intel Sandy Bridge (2nd gen Core, model 42/45) and newer CPUs.

if omarchy-hw-intel; then
  # Check if Sandy Bridge or newer (model >= 42). Sandy Bridge: model 42 (mobile), 45 (desktop)
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  if ((cpu_model >= 42)) && omarchy-battery-present; then
    omarchy-pkg-add thermald
    sudo systemctl enable --now thermald
  fi
fi
