# Fix flaky 3.5 mm jack hotplug on the MSI X370 GAMING PLUS with ALC892.
# This hardware needs HDA powersave disabled for reliable jack detection.

if omarchy-hw-msi-x370-gaming-plus &&
  grep -q "Codec: Realtek ALC892" /proc/asound/card*/codec* 2>/dev/null &&
  grep -q "Subsystem Id: 0x1462fa33" /proc/asound/card*/codec* 2>/dev/null; then
  MODPROBE_FIX_PATH="/etc/modprobe.d/90-snd-hda-intel-jackfix.conf"
  MODPROBE_FIX_CONTENT="options snd_hda_intel power_save=0 power_save_controller=N"

  sudo mkdir -p /etc/modprobe.d

  if [[ $(sudo cat "$MODPROBE_FIX_PATH" 2>/dev/null || true) != "$MODPROBE_FIX_CONTENT" ]]; then
    echo "$MODPROBE_FIX_CONTENT" | sudo tee "$MODPROBE_FIX_PATH" >/dev/null
  fi

  if [[ -e /sys/module/snd_hda_intel/parameters/power_save ]] &&
    [[ -e /sys/module/snd_hda_intel/parameters/power_save_controller ]]; then
    sudo sh -c 'echo 0 > /sys/module/snd_hda_intel/parameters/power_save'
    sudo sh -c 'echo N > /sys/module/snd_hda_intel/parameters/power_save_controller'
  fi
fi
