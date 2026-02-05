# Fix internal mic gain on ASUS ROG laptops with Realtek ALC285.
# The mic boost is way too high by default, causing clipping.
# Sets levels and stores ALSA state so it persists across reboots.

if omarchy-hw-asus-rog; then
  for card in /proc/asound/card*/codec*; do
    if grep -q "ALC285" "$card" 2>/dev/null; then
      cardnum=$(echo "$card" | grep -oP 'card\K\d+')
      amixer -c "$cardnum" set 'Internal Mic Boost' 0 >/dev/null 2>&1 || true
      amixer -c "$cardnum" set 'Capture' 70% >/dev/null 2>&1 || true
      sudo alsactl store "$cardnum" 2>/dev/null || true
      break
    fi
  done
fi
